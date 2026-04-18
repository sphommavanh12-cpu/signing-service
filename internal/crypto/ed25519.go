package crypto

import (
	"crypto/ed25519"
	"encoding/hex"
	"fmt"
)

type SigningKey struct {
	privateKey ed25519.PrivateKey
	publicKey  ed25519.PublicKey
}

func NewSigningKeyFromSeed(seed []byte) (*SigningKey, error) {
	if len(seed) != 32 {
		return nil, fmt.Errorf("seed must be exactly 32 bytes, got %d", len(seed))
	}
	privateKey := ed25519.NewKeyFromSeed(seed)
	publicKey := privateKey.Public().(ed25519.PublicKey)
	return &SigningKey{
		privateKey: privateKey,
		publicKey:  publicKey,
	}, nil
}

func (k *SigningKey) Sign(message []byte) ([]byte, error) {
	if k.privateKey == nil {
		return nil, fmt.Errorf("signing key not initialized")
	}
	signature := ed25519.Sign(k.privateKey, message)
	if len(signature) != 64 {
		return nil, fmt.Errorf("invalid signature length: expected 64, got %d", len(signature))
	}
	return signature, nil
}

func (k *SigningKey) PublicKeyHex() string {
	return hex.EncodeToString(k.publicKey)
}

func (k *SigningKey) PublicKeyBytes() []byte {
	return k.publicKey
}

func Verify(publicKeyBytes []byte, message []byte, signature []byte) error {
	if len(signature) != 64 {
		return fmt.Errorf("invalid signature length: expected 64, got %d", len(signature))
	}
	if !ed25519.Verify(ed25519.PublicKey(publicKeyBytes), message, signature) {
		return fmt.Errorf("signature verification failed")
	}
	return nil
}
