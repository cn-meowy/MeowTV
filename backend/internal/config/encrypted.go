package config

import (
	"fmt"
	"strings"
)

// encKey is the global encryption key used for decrypting EncryptedString values.
// It is set during config.Load() via MEOWTV_ENCRYPTION_KEY or encryption.key.
// If not set, encrypted values will fail to decrypt (returning an error in Plain()).
var encKey string

// SetEncryptionKey sets the global encryption key used for decrypting EncryptedString values.
// This is typically called during config.Load().
func SetEncryptionKey(key string) {
	encKey = key
}

// GetEncryptionKey returns the current encryption key.
func GetEncryptionKey() string {
	return encKey
}

// EncryptedString is a string type that supports encrypted values in config files.
// Values prefixed with "ENC:" are considered encrypted and will be decrypted on Plain().
// Plain values (without prefix) are returned as-is.
//
// Usage in YAML:
//
//	password: "ENC:aGd4c3Rlc3Q="   # encrypted
//	password: "plaintext"           # plain text (backward compatible)
type EncryptedString string

// Plain returns the decrypted plaintext value.
// If the value is not encrypted (no ENC: prefix), it returns the value as-is.
// If the value is encrypted but no encryption key is set, it returns an error.
func (e EncryptedString) Plain() (string, error) {
	if !e.IsEncrypted() {
		return string(e), nil
	}

	// Strip the ENC: prefix to get the ciphertext
	ciphertext := strings.TrimPrefix(string(e), EncryptedPrefix)
	if ciphertext == "" {
		return "", fmt.Errorf("config: encrypted value is empty after stripping ENC: prefix")
	}

	// Try to decrypt with the global encryption key
	if encKey == "" {
		return "", fmt.Errorf("config: encryption key not set, cannot decrypt ENC: value; set MEOWTV_ENCRYPTION_KEY environment variable or encryption.key in config")
	}

	return Decrypt(ciphertext, encKey)
}

// MustPlain is like Plain but panics on error.
// Use only when you are certain the value is valid or can accept a panic.
func (e EncryptedString) MustPlain() string {
	result, err := e.Plain()
	if err != nil {
		panic(err)
	}
	return result
}

// IsEncrypted returns true if the value is prefixed with "ENC:".
func (e EncryptedString) IsEncrypted() bool {
	return strings.HasPrefix(string(e), EncryptedPrefix)
}

// String returns the raw string value without decryption.
// This is safe for logging (won't expose decrypted secrets).
func (e EncryptedString) String() string {
	return string(e)
}

// MarshalYAML implements yaml.Marshaler.
func (e EncryptedString) MarshalYAML() (interface{}, error) {
	return string(e), nil
}

// UnmarshalYAML implements yaml.Unmarshaler.
func (e *EncryptedString) UnmarshalYAML(unmarshal func(interface{}) error) error {
	var s string
	if err := unmarshal(&s); err != nil {
		return err
	}
	*e = EncryptedString(s)
	return nil
}

// MarshalText implements encoding.TextMarshaler.
func (e EncryptedString) MarshalText() ([]byte, error) {
	return []byte(e), nil
}

// UnmarshalText implements encoding.TextUnmarshaler.
func (e *EncryptedString) UnmarshalText(text []byte) error {
	*e = EncryptedString(text)
	return nil
}
