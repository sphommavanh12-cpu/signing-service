package api

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"signing-service/internal/crypto"
	"signing-service/internal/github"
	"time"
)

type SignRequest struct {
	ChainHead string `json:"chain_head"`
}

type SignResponse struct {
	Signature       string `json:"signature"`
	KeyVersion      string `json:"key_version"`
	Timestamp       string `json:"timestamp"`
	ChainHeadSha256 string `json:"chain_head_sha256"`
}

type StatusResponse struct {
	Status              string  `json:"status"`
	KeyVersion          string  `json:"key_version"`
	LastSigningTime     *string `json:"last_signing_time"`
	GitHubConnectivity  bool    `json:"github_connectivity"`
	Uptime              string  `json:"uptime"`
	ListeningOnPort     int     `json:"listening_on_port"`
	StatusPortListening int     `json:"status_port_listening"`
}

type Handler struct {
	signingKey     *crypto.SigningKey
	keyVersion     string
	githubClient   *github.Client
	startTime      time.Time
	lastSigningTime *time.Time
	statusPort     int
}

func NewHandler(signingKey *crypto.SigningKey, keyVersion string, githubClient *github.Client, statusPort int) *Handler {
	return &Handler{
		signingKey:   signingKey,
		keyVersion:   keyVersion,
		githubClient: githubClient,
		startTime:    time.Now(),
		statusPort:   statusPort,
	}
}

func (h *Handler) HandleSignRequest(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if err := h.githubClient.CheckConnectivity(); err != nil {
		h.logSigningEvent("FAILED", "", err.Error())
		http.Error(w, fmt.Sprintf("GitHub connectivity check failed: %v", err), http.StatusServiceUnavailable)
		return
	}
	var req SignRequest
	body, _ := io.ReadAll(r.Body)
	if err := json.Unmarshal(body, &req); err != nil {
		http.Error(w, "Invalid JSON", http.StatusBadRequest)
		return
	}
	if req.ChainHead == "" {
		http.Error(w, "chain_head cannot be empty", http.StatusBadRequest)
		return
	}
	chainHeadSha256 := sha256.Sum256([]byte(req.ChainHead))
	chainHeadSha256Hex := hex.EncodeToString(chainHeadSha256[:])
	signature, err := h.signingKey.Sign([]byte(req.ChainHead))
	if err != nil {
		h.logSigningEvent("FAILED", req.ChainHead, err.Error())
		http.Error(w, fmt.Sprintf("Signing failed: %v", err), http.StatusInternalServerError)
		return
	}
	if len(signature) != 64 {
		h.logSigningEvent("FAILED", req.ChainHead, fmt.Sprintf("invalid signature length: %d", len(signature)))
		http.Error(w, "Signature validation failed", http.StatusInternalServerError)
		return
	}
	now := time.Now()
	h.lastSigningTime = &now
	response := SignResponse{
		Signature:       hex.EncodeToString(signature),
		KeyVersion:      h.keyVersion,
		Timestamp:       now.Format(time.RFC3339Nano),
		ChainHeadSha256: chainHeadSha256Hex,
	}
	h.logSigningEvent("SUCCESS", req.ChainHead, "")
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

func (h *Handler) HandleStatus(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	githubOK := h.githubClient.CheckConnectivity() == nil
	var lastSigningTimeStr *string
	if h.lastSigningTime != nil {
		ts := h.lastSigningTime.Format(time.RFC3339Nano)
		lastSigningTimeStr = &ts
	}
	response := StatusResponse{
		Status:              "healthy",
		KeyVersion:          h.keyVersion,
		LastSigningTime:     lastSigningTimeStr,
		GitHubConnectivity:  githubOK,
		Uptime:              time.Since(h.startTime).String(),
		ListeningOnPort:     9999,
		StatusPortListening: h.statusPort,
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

func (h *Handler) logSigningEvent(status string, chainHead string, errorMsg string) {
	timestamp := time.Now().Format(time.RFC3339Nano)
	logEntry := map[string]interface{}{
		"timestamp":   timestamp,
		"status":      status,
		"key_version": h.keyVersion,
	}
	if chainHead != "" {
		hash := sha256.Sum256([]byte(chainHead))
		logEntry["chain_head_sha256"] = hex.EncodeToString(hash[:])
	}
	if errorMsg != "" {
		logEntry["error"] = errorMsg
	}
	logJSON, _ := json.Marshal(logEntry)
	fmt.Println(string(logJSON))
}
