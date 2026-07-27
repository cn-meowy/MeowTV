package util

import (
	"errors"
	"fmt"
	"math/big"
)

// Base58 字母表（Bitcoin 标准）
const base58Alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"

var base58AlphabetMap = make(map[byte]int)

func init() {
	for i := 0; i < len(base58Alphabet); i++ {
		base58AlphabetMap[base58Alphabet[i]] = i
	}
}

// Decode 将 Base58 编码的字符串解码为字节切片
// 使用 Bitcoin 字母表，前导 '1' 还原为前导零字节
func Decode(input string) ([]byte, error) {
	if len(input) == 0 {
		return nil, errors.New("empty base58 input")
	}

	// 统计前导 '1'（在 Base58 中 '1' 代表零字节）
	leadingZeros := 0
	for _, c := range input {
		if c == '1' {
			leadingZeros++
		} else {
			break
		}
	}

	// 从 Base58 转换为大整数
	result := big.NewInt(0)
	for _, c := range input {
		idx, ok := base58AlphabetMap[byte(c)]
		if !ok {
			return nil, fmt.Errorf("invalid base58 character: %c", c)
		}
		result.Mul(result, big.NewInt(58))
		result.Add(result, big.NewInt(int64(idx)))
	}

	// 将大整数转换为字节切片
	decoded := result.Bytes()

	// 添加前导零字节
	output := make([]byte, leadingZeros+len(decoded))
	copy(output[leadingZeros:], decoded)

	return output, nil
}
