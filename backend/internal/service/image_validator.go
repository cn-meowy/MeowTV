package service

import (
	"bytes"
	"encoding/binary"
	"errors"
	"fmt"
	"image"
	_ "image/gif"
	_ "image/jpeg"
	_ "image/png"
)

// ErrImageCorrupted 表示图片数据不完整或损坏
var ErrImageCorrupted = errors.New("image data corrupted or incomplete")

// validateImage 校验图片二进制数据是否完整可用。
// 通过尝试完整解码来判断：jpeg/png/gif 走 image.Decode，webp 走 magic number + 长度校验。
// 返回 nil 表示图片完整可用；返回 ErrImageCorrupted 包装错误表示损坏。
func validateImage(data []byte) error {
	if len(data) == 0 {
		return fmt.Errorf("%w: empty data", ErrImageCorrupted)
	}

	// webp 因 Go 标准库不支持解码，通过 magic number + 文件声明长度校验
	if isWebP(data) {
		return validateWebP(data)
	}

	// jpeg/png/gif：尝试完整解码，能解码说明数据完整
	reader := bytes.NewReader(data)
	if _, _, err := image.Decode(reader); err != nil {
		return fmt.Errorf("%w: decode failed: %v", ErrImageCorrupted, err)
	}
	return nil
}

// validateImageWithLength 校验图片完整性，并在响应头提供 Content-Length 时比对待读取字节数。
// contentLength <= 0 时跳过长度比对，仅做解码校验。
func validateImageWithLength(data []byte, contentLength int64) error {
	if contentLength > 0 && int64(len(data)) != contentLength {
		return fmt.Errorf("%w: content-length mismatch, expected=%d actual=%d",
			ErrImageCorrupted, contentLength, len(data))
	}
	return validateImage(data)
}

// isWebP 判断数据是否为 webp 格式（RIFF....WEBP）。
func isWebP(data []byte) bool {
	return len(data) >= 12 &&
		bytes.Equal(data[0:4], []byte("RIFF")) &&
		bytes.Equal(data[8:12], []byte("WEBP"))
}

// validateWebP 校验 webp 数据完整性：头部 + 声明文件长度比对。
func validateWebP(data []byte) error {
	if len(data) < 12 {
		return fmt.Errorf("%w: webp too short", ErrImageCorrupted)
	}
	// RIFF 文件总长度 = 字段值 + 8（RIFF 标识 + 长度字段本身）
	declared := int64(binary.LittleEndian.Uint32(data[4:8])) + 8
	if int64(len(data)) < declared {
		return fmt.Errorf("%w: webp truncated, declared=%d actual=%d",
			ErrImageCorrupted, declared, len(data))
	}
	return nil
}
