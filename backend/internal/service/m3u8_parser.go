package service

import (
	"bufio"
	"bytes"
	"crypto/aes"
	"crypto/cipher"
	"encoding/hex"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/url"
	"strconv"
	"strings"
)

// M3u8Info m3u8 解析结果
type M3u8Info struct {
	IsMaster   bool
	IsVOD      bool          // 是否为 VOD（有 EXT-X-ENDLIST 标签），无此标签可能为直播流
	Variants   []VariantInfo // master playlist 多码率
	Segments   []SegmentInfo // media playlist 分片列表
	Encryption *EncryptionInfo
	Duration   float64 // 总时长秒
	MediaURL   string  // 如果是 master，选择的最优 media playlist URL
	RawContent string  // media playlist 原始文本内容（用于 rewriteM3U8 行级替换）
}

// VariantInfo master playlist 中的码率变体
type VariantInfo struct {
	Bandwidth  int
	Resolution string
	URI        string
}

// SegmentInfo TS 分片信息
type SegmentInfo struct {
	URL        string
	Duration   float64
	Index      int
	Encryption *EncryptionInfo // 该分片专属的加密信息，nil 表示未加密
}

// EncryptionInfo AES-128 加密信息
type EncryptionInfo struct {
	Method string // AES-128
	KeyURI string
	IV     []byte
	Key    []byte // 解密后的 key
}

// M3u8Parser m3u8 解析器
type M3u8Parser struct {
	httpClient *http.Client
}

// NewM3u8Parser 创建 m3u8 解析器
func NewM3u8Parser(httpClient *http.Client) *M3u8Parser {
	return &M3u8Parser{httpClient: httpClient}
}

// Parse 解析 m3u8 URL，返回统一的分片列表
// 如果是 master playlist，自动选择最高码率的 media playlist 并解析
func (p *M3u8Parser) Parse(m3u8URL string) (*M3u8Info, error) {
	content, err := p.fetchContent(m3u8URL)
	if err != nil {
		return nil, fmt.Errorf("fetch m3u8 content: %w", err)
	}

	info := &M3u8Info{}

	if isMasterPlaylist(content) {
		info.IsMaster = true
		variants, err := p.parseMasterPlaylist(content, m3u8URL)
		if err != nil {
			return nil, fmt.Errorf("parse master playlist: %w", err)
		}
		info.Variants = variants

		// 选择最高码率
		best := selectBestVariant(variants)
		if best == nil {
			return nil, fmt.Errorf("no variant found in master playlist")
		}

		// 递归解析 media playlist
		mediaURL := resolveURL(m3u8URL, best.URI)
		info.MediaURL = mediaURL
		mediaContent, err := p.fetchContent(mediaURL)
		if err != nil {
			return nil, fmt.Errorf("fetch media playlist: %w", err)
		}

		segments, encryption, duration, isVOD, err := p.parseMediaPlaylist(mediaContent, mediaURL)
		if err != nil {
			return nil, fmt.Errorf("parse media playlist: %w", err)
		}
		info.Segments = segments
		info.Encryption = encryption
		info.Duration = duration
		info.IsVOD = isVOD
		info.RawContent = mediaContent // 保存原始 media playlist 内容供 rewriteM3U8 行级替换
	} else {
		segments, encryption, duration, isVOD, err := p.parseMediaPlaylist(content, m3u8URL)
		if err != nil {
			return nil, fmt.Errorf("parse media playlist: %w", err)
		}
		info.Segments = segments
		info.Encryption = encryption
		info.Duration = duration
		info.IsVOD = isVOD
		info.RawContent = content // 保存原始 media playlist 内容供 rewriteM3U8 行级替换
	}

	// 如果有全局加密，获取解密 key
	if info.Encryption != nil && info.Encryption.Method == "AES-128" {
		key, err := p.fetchEncryptionKey(info.Encryption.KeyURI)
		if err != nil {
			return nil, fmt.Errorf("fetch encryption key: %w", err)
		}
		info.Encryption.Key = key
	}

	// 获取分片级加密 key（去重，避免重复请求同一个 key URI）
	encKeyCache := make(map[string][]byte)
	if info.Encryption != nil && info.Encryption.Method == "AES-128" {
		encKeyCache[info.Encryption.KeyURI] = info.Encryption.Key
	}
	for i := range info.Segments {
		seg := &info.Segments[i]
		if seg.Encryption == nil || seg.Encryption.Method != "AES-128" {
			continue
		}
		// 如果分片加密与全局加密相同，复用全局 key
		if info.Encryption != nil && seg.Encryption.KeyURI == info.Encryption.KeyURI {
			seg.Encryption.Key = info.Encryption.Key
			continue
		}
		// 从缓存获取或请求新的 key
		if key, ok := encKeyCache[seg.Encryption.KeyURI]; ok {
			seg.Encryption.Key = key
		} else {
			key, err := p.fetchEncryptionKey(seg.Encryption.KeyURI)
			if err != nil {
				return nil, fmt.Errorf("fetch encryption key for segment %d: %w", seg.Index, err)
			}
			encKeyCache[seg.Encryption.KeyURI] = key
			seg.Encryption.Key = key
		}
	}

	slog.Info("m3u8 parsed",
		"url", m3u8URL,
		"is_master", info.IsMaster,
		"segments", len(info.Segments),
		"duration", fmt.Sprintf("%.1f", info.Duration),
		"encrypted", info.Encryption != nil,
	)

	return info, nil
}

// fetchContent 获取 m3u8 文本内容
func (p *M3u8Parser) fetchContent(rawURL string) (string, error) {
	resp, err := p.httpClient.Get(rawURL)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("HTTP %d", resp.StatusCode)
	}

	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}
	return string(data), nil
}

// isMasterPlaylist 判断是否为 master playlist
func isMasterPlaylist(content string) bool {
	scanner := bufio.NewScanner(strings.NewReader(content))
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if strings.HasPrefix(line, "#EXT-X-STREAM-INF:") {
			return true
		}
	}
	return false
}

// parseMasterPlaylist 解析 master playlist
func (p *M3u8Parser) parseMasterPlaylist(content, baseURL string) ([]VariantInfo, error) {
	var variants []VariantInfo
	scanner := bufio.NewScanner(strings.NewReader(content))

	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if !strings.HasPrefix(line, "#EXT-X-STREAM-INF:") {
			continue
		}

		v := VariantInfo{}
		attrs := parseAttributes(line[len("#EXT-X-STREAM-INF:"):])
		if bw, ok := attrs["BANDWIDTH"]; ok {
			v.Bandwidth, _ = strconv.Atoi(bw)
		}
		if res, ok := attrs["RESOLUTION"]; ok {
			v.Resolution = res
		}

		// 下一行非空行是 URI
		for scanner.Scan() {
			uri := strings.TrimSpace(scanner.Text())
			if uri != "" && !strings.HasPrefix(uri, "#") {
				v.URI = resolveURL(baseURL, uri)
				break
			}
		}

		variants = append(variants, v)
	}

	if len(variants) == 0 {
		return nil, fmt.Errorf("no variants found")
	}
	return variants, nil
}

// parseMediaPlaylist 解析 media playlist
func (p *M3u8Parser) parseMediaPlaylist(content, baseURL string) ([]SegmentInfo, *EncryptionInfo, float64, bool, error) {
	var segments []SegmentInfo
	var encryption *EncryptionInfo
	var totalDuration float64
	var currentDuration float64
	var isVOD bool
	segIndex := 0

	scanner := bufio.NewScanner(strings.NewReader(content))

	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())

		// 检测 EXT-X-ENDLIST（标识 VOD 结束）
		if strings.HasPrefix(line, "#EXT-X-ENDLIST") {
			isVOD = true
			continue
		}

		// 解析 EXT-X-KEY
		if strings.HasPrefix(line, "#EXT-X-KEY:") {
			attrs := parseAttributes(line[len("#EXT-X-KEY:"):])
			method := attrs["METHOD"]
			if method == "NONE" {
				encryption = nil
				continue
			}
			if method == "AES-128" {
				encryption = &EncryptionInfo{
					Method: method,
				}
				if keyURI, ok := attrs["URI"]; ok {
					encryption.KeyURI = resolveURL(baseURL, keyURI)
				}
				if iv, ok := attrs["IV"]; ok {
					encryption.IV = parseIV(iv)
				}
			}
			continue
		}

		// 解析 EXTINF
		if strings.HasPrefix(line, "#EXTINF:") {
			durStr := strings.TrimSuffix(line[len("#EXTINF:"):], ",")
			currentDuration, _ = strconv.ParseFloat(durStr, 64)
			continue
		}

		// 跳过其他标签和空行
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		// 分片 URL
		segURL := resolveURL(baseURL, line)
		segments = append(segments, SegmentInfo{
			URL:        segURL,
			Duration:   currentDuration,
			Index:      segIndex,
			Encryption: encryption, // 关联当前加密状态（HLS 允许不同分片使用不同加密）
		})
		totalDuration += currentDuration
		segIndex++
	}

	if len(segments) == 0 {
		return nil, nil, 0, false, fmt.Errorf("no segments found")
	}

	return segments, encryption, totalDuration, isVOD, nil
}

// selectBestVariant 选择最高码率的变体
func selectBestVariant(variants []VariantInfo) *VariantInfo {
	if len(variants) == 0 {
		return nil
	}
	best := &variants[0]
	for i := 1; i < len(variants); i++ {
		if variants[i].Bandwidth > best.Bandwidth {
			best = &variants[i]
		}
	}
	return best
}

// resolveURL 将相对路径转为绝对 URL
func resolveURL(baseURL, ref string) string {
	// 已经是绝对 URL
	if strings.HasPrefix(ref, "http://") || strings.HasPrefix(ref, "https://") {
		return ref
	}

	base, err := url.Parse(baseURL)
	if err != nil {
		return ref
	}

	refURL, err := url.Parse(ref)
	if err != nil {
		return ref
	}

	return base.ResolveReference(refURL).String()
}

// parseAttributes 解析 HLS 属性字符串
// 例如: METHOD=AES-128,URI="https://key.example.com",IV=0x1234
func parseAttributes(raw string) map[string]string {
	attrs := make(map[string]string)
	i := 0
	for i < len(raw) {
		// 找 key
		eqIdx := strings.Index(raw[i:], "=")
		if eqIdx < 0 {
			break
		}
		key := raw[i : i+eqIdx]
		i += eqIdx + 1

		if i >= len(raw) {
			break
		}

		// 值可能是引号包裹或裸值
		var value string
		if raw[i] == '"' {
			// 引号值
			endIdx := strings.Index(raw[i+1:], "\"")
			if endIdx < 0 {
				break
			}
			value = raw[i+1 : i+1+endIdx]
			i += endIdx + 2 // skip closing quote
		} else {
			// 裸值，到逗号或行尾
			commaIdx := strings.Index(raw[i:], ",")
			if commaIdx < 0 {
				value = raw[i:]
				i = len(raw)
			} else {
				value = raw[i : i+commaIdx]
				i += commaIdx + 1
			}
		}

		attrs[key] = value

		// 跳过逗号
		if i < len(raw) && raw[i] == ',' {
			i++
		}
	}
	return attrs
}

// parseIV 解析 IV 值 (0x 开头的十六进制)
func parseIV(ivStr string) []byte {
	ivStr = strings.TrimPrefix(ivStr, "0x")
	ivStr = strings.TrimPrefix(ivStr, "0X")
	data, err := hex.DecodeString(ivStr)
	if err != nil {
		return nil
	}
	return data
}

// fetchEncryptionKey 获取 AES-128 解密 key
func (p *M3u8Parser) fetchEncryptionKey(keyURI string) ([]byte, error) {
	resp, err := p.httpClient.Get(keyURI)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("HTTP %d", resp.StatusCode)
	}

	return io.ReadAll(resp.Body)
}

// DecryptSegment 解密 AES-128 加密的 TS 分片
func DecryptSegment(data []byte, key, iv []byte) ([]byte, error) {
	// 验证 Key 长度
	if len(key) != aes.BlockSize {
		return nil, fmt.Errorf("key length %d is not %d bytes", len(key), aes.BlockSize)
	}

	// 验证数据长度 - 防止 panic: crypto/cipher: input not full blocks
	if len(data) == 0 {
		return nil, fmt.Errorf("input data is empty")
	}
	if len(data) < aes.BlockSize {
		return nil, fmt.Errorf("input length %d is less than block size %d", len(data), aes.BlockSize)
	}
	if len(data)%aes.BlockSize != 0 {
		return nil, fmt.Errorf("input length %d is not a multiple of block size %d", len(data), aes.BlockSize)
	}

	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, fmt.Errorf("create cipher: %w", err)
	}

	// 验证 IV 长度
	if len(iv) != aes.BlockSize {
		return nil, fmt.Errorf("IV length %d is not %d bytes", len(iv), aes.BlockSize)
	}

	stream := cipher.NewCBCDecrypter(block, iv)
	decrypted := make([]byte, len(data))
	stream.CryptBlocks(decrypted, data)

	// 移除 PKCS7 padding
	result, err := pkcs7Unpad(decrypted)
	if err != nil {
		return nil, fmt.Errorf("pkcs7 unpadding failed: %w", err)
	}

	return result, nil
}

// pkcs7Unpad 移除 PKCS7 填充
func pkcs7Unpad(data []byte) ([]byte, error) {
	if len(data) == 0 {
		return nil, fmt.Errorf("data is empty")
	}
	padding := int(data[len(data)-1])
	if padding == 0 || padding > len(data) || padding > aes.BlockSize {
		return nil, fmt.Errorf("invalid padding value %d (data length %d)", padding, len(data))
	}
	for i := len(data) - padding; i < len(data); i++ {
		if data[i] != byte(padding) {
			return nil, fmt.Errorf("padding mismatch at index %d: expected %d, got %d", i, padding, data[i])
		}
	}
	return data[:len(data)-padding], nil
}

// IsTSPacketData 检查数据是否以 MPEG-TS 同步字节 0x47 开头
// 加密后的数据几乎不会以 0x47 开头，因此可以用来判断分片是否实际未加密
func IsTSPacketData(data []byte) bool {
	if len(data) < 4 {
		return false
	}
	// MPEG-TS 包以同步字节 0x47 开头
	// 进一步验证：检查 188 字节偏移处是否也是同步字节（标准 TS 包大小）
	if data[0] != 0x47 {
		return false
	}
	// 如果数据足够长，验证第二个 TS 包的同步字节
	if len(data) >= 188+1 && data[188] != 0x47 {
		return false
	}
	return true
}

// MergeSegments 合并所有 TS 分片数据
func MergeSegments(segments [][]byte) []byte {
	totalSize := 0
	for _, seg := range segments {
		totalSize += len(seg)
	}
	merged := bytes.NewBuffer(make([]byte, 0, totalSize))
	for _, seg := range segments {
		merged.Write(seg)
	}
	return merged.Bytes()
}
