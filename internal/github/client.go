package github

import (
	"fmt"
	"io"
	"net/http"
	"time"
)

type Client struct {
	token   string
	timeout time.Duration
}

func NewClient(token string) *Client {
	return &Client{
		token:   token,
		timeout: 10 * time.Second,
	}
}

func (c *Client) CheckConnectivity() error {
	client := &http.Client{Timeout: c.timeout}
	req, err := http.NewRequest("GET", "https://api.github.com/", nil)
	if err != nil {
		return fmt.Errorf("failed to create request: %w", err)
	}
	if c.token != "" {
		req.Header.Set("Authorization", fmt.Sprintf("token %s", c.token))
	}
	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("github connectivity check failed: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 256))
		return fmt.Errorf("github api error: %d %s", resp.StatusCode, string(body))
	}
	return nil
}

func (c *Client) GetFileContent(owner, repo, path string) ([]byte, error) {
	url := fmt.Sprintf("https://raw.githubusercontent.com/%s/%s/main/%s", owner, repo, path)
	client := &http.Client{Timeout: c.timeout}
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}
	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch from github: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("github returned %d for %s", resp.StatusCode, path)
	}
	content, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response: %w", err)
	}
	return content, nil
}
