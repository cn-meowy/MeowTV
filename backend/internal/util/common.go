package util

import (
	"encoding/json"
	"regexp"
	"strconv"
)

// FlexString 可同时从 JSON 字符串或数字反序列化为 string 的自定义类型。
// MacCMS 不同站点的 API 实现不一致，某些字段可能返回数字也可能返回字符串，
// FlexString 能兼容两种情况，统一转为 string 存储。
type FlexString string

// UnmarshalJSON 实现 json.Unmarshaler 接口，兼容 JSON 字符串和数字
func (f *FlexString) UnmarshalJSON(data []byte) error {
	// 尝试作为字符串解析
	var s string
	if err := json.Unmarshal(data, &s); err == nil {
		*f = FlexString(s)
		return nil
	}
	// 尝试作为数字解析
	var n json.Number
	if err := json.Unmarshal(data, &n); err == nil {
		*f = FlexString(n.String())
		return nil
	}
	// 兜底：直接转为字符串
	*f = FlexString(string(data))
	return nil
}

// MarshalJSON 实现 json.Marshaler 接口，统一输出为 JSON 字符串
func (f FlexString) MarshalJSON() ([]byte, error) {
	return json.Marshal(string(f))
}

// String 返回字符串值
func (f FlexString) String() string {
	return string(f)
}

// Int 转换为 int，解析失败返回 0
func (f FlexString) Int() int {
	n, _ := strconv.Atoi(string(f))
	return n
}

// Int64 转换为 int64，解析失败返回 0
func (f FlexString) Int64() int64 {
	n, _ := strconv.ParseInt(string(f), 10, 64)
	return n
}

func Ternary(cond bool, a, b int) int {
	if cond {
		return a
	}
	return b
}

func NoSearch(str string) bool {
	if str == "" {
		return false
	}
	compile, _ := regexp.Compile(`无法搜索|无搜索|403|暂不支持搜索|禁止搜索`)
	return compile.MatchString(str)
}
