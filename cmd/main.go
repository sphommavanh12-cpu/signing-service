package main

import (
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"signing-service/internal/api"
	"signing-service/internal/crypto"
	"signing-service/internal/github"
	"time"
)

func main() {
	// CP-3 SCOPE PLACEHOLDER: Signing Key Initialization
	// For CP-3, the signing key is derived from a test seed (hardcoded placeholder).
	// Production implementation requires:
	// - AES-256-GCM encrypted key storage
	// - Argon2 KDF from passphrase
	// - systemd LoadCredential for passphrase
	// - Key decryption at startup only
	// This full vault integration is CP-4 scope (REQ-013 through REQ-015).
	// CP-3 scope is systemd deployment with method-level separation and security directives.

	bind := flag.String("bind", "100.118.135.73", "Tailscale IP address to bind to")
	port := flag.Int("port", 9999, "Port for signing requests")
	statusPort := flag.Int("status-port", 9998, "Port for status endpoint")
	keyVersion := flag.String("key-version", "v1", "Key version identifier")
	githubToken := flag.String("github-token", "", "GitHub API token (optional)")
	flag.Parse()

	if *bind == "0.0.0.0" || *bind == "::" {
		log.Fatal("bind address cannot be a wildcard (0.0.0.0 or ::). Must be a specific Tailscale IP.")
	}

	testSeed := make([]byte, 32)
	for i := range testSeed {
		testSeed[i] = byte((i + 1) % 256)
	}

	signingKey, err := crypto.NewSigningKeyFromSeed(testSeed)
	if err != nil {
		log.Fatalf("Failed to create signing key: %v", err)
	}

	fmt.Printf("Signing service initialized\n")
	fmt.Printf("  Public Key: %s\n", signingKey.PublicKeyHex())
	fmt.Printf("  Key Version: %s\n", *keyVersion)
	fmt.Printf("  Binding to: %s:%d\n", *bind, *port)
	fmt.Printf("  Status port: %d\n", *statusPort)

	githubClient := github.NewClient(*githubToken)

	if err := githubClient.CheckConnectivity(); err != nil {
		log.Fatalf("FAIL CLOSED: GitHub connectivity check failed at startup: %v", err)
	}
	fmt.Println("GitHub connectivity verified")

	handler := api.NewHandler(signingKey, *keyVersion, githubClient, *statusPort)

	mux := http.NewServeMux()
	mux.HandleFunc("/sign", handler.HandleSignRequest)
	mux.HandleFunc("/status", handler.HandleStatus)

	signingAddr := fmt.Sprintf("%s:%d", *bind, *port)
	signingServer := &http.Server{
		Addr:         signingAddr,
		Handler:      mux,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	statusAddr := fmt.Sprintf("%s:%d", *bind, *statusPort)
	statusServer := &http.Server{
		Addr:         statusAddr,
		Handler:      mux,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	for _, addr := range []string{signingAddr, statusAddr} {
		listener, err := net.Listen("tcp", addr)
		if err != nil {
			log.Fatalf("Cannot bind to %s: %v", addr, err)
		}
		listener.Close()
	}

	fmt.Printf("Starting signing service on %s\n", signingAddr)
	fmt.Printf("Starting status endpoint on %s\n", statusAddr)

	go func() {
		if err := signingServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Signing server error: %v", err)
		}
	}()

	go func() {
		if err := statusServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Status server error: %v", err)
		}
	}()

	select {}
}
