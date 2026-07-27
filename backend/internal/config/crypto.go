package config

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"fmt"
	"io"
)

const (
	// EncryptedPrefix is the prefix for encrypted values in config files.
	EncryptedPrefix = "ENC:"
	// NonceSize is the size of the GCM nonce in bytes.
	NonceSize = 12
	// TagSize is the size of the GCM authentication tag in bytes.
	TagSize = 16
)

// ErrInvalidCiphertext is returned when ciphertext cannot be decrypted.
var ErrInvalidCiphertext = errors.New("config: invalid ciphertext")

// deriveKey derives a 32-byte key from the given password using SHA-256.
func deriveKey(password string) []byte {
	h := sha256.Sum256([]byte(password))
	return h[:]
}

// Encrypt encrypts plaintext using AES-256-GCM with the given key.
// The output format is: base64(nonce + ciphertext + tag).
// If key is empty, it returns the plaintext as-is without encryption.
// If plaintext is already prefixed with ENC:, it returns it unchanged.
func Encrypt(plaintext, key string) (string, error) {
	if plaintext == "" {
		return "", nil
	}
	// If no key provided, return plaintext as-is (no encryption)
	if key == "" {
		return plaintext, nil
	}

	k := deriveKey(key)
	block, err := aes.NewCipher(k)
	if err != nil {
		return "", fmt.Errorf("failed to create cipher: %w", err)
	}

	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", fmt.Errorf("failed to create GCM: %w", err)
	}

	nonce := make([]byte, NonceSize)
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return "", fmt.Errorf("failed to generate nonce: %w", err)
	}

	ciphertext := gcm.Seal(nonce, nonce, []byte(plaintext), nil)
	return base64.StdEncoding.EncodeToString(ciphertext), nil
}

// Decrypt decrypts ciphertext that was encrypted with Encrypt.
// It accepts both raw base64 ciphertext and ENC:prefixed values.
// If key is empty, it returns the ciphertext as-is (no decryption).
func Decrypt(ciphertext, key string) (string, error) {
	if ciphertext == "" {
		return "", nil
	}
	// If no key provided, return ciphertext as-is
	if key == "" {
		return ciphertext, nil
	}

	data, err := base64.StdEncoding.DecodeString(ciphertext)
	if err != nil {
		return "", fmt.Errorf("failed to decode base64: %w", err)
	}

	if len(data) < NonceSize+TagSize {
		return "", ErrInvalidCiphertext
	}

	k := deriveKey(key)
	block, err := aes.NewCipher(k)
	if err != nil {
		return "", fmt.Errorf("failed to create cipher: %w", err)
	}

	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", fmt.Errorf("failed to create GCM: %w", err)
	}

	nonce := data[:NonceSize]
	encrypted := data[NonceSize:]

	plaintext, err := gcm.Open(nil, nonce, encrypted, nil)
	if err != nil {
		return "", fmt.Errorf("failed to decrypt: %w", err)
	}

	return string(plaintext), nil
}

// MustDecrypt is like Decrypt but panics on error.
// Use only when you are certain the ciphertext is valid.
func MustDecrypt(ciphertext, key string) string {
	result, err := Decrypt(ciphertext, key)
	if err != nil {
		panic(err)
	}
	return result
}
