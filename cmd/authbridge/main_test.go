package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestHandleAuth(t *testing.T) {
	cases := []struct {
		name       string
		query      string
		wantResult int
		wantUserId string
	}{
		{"with identity", "?identity=test-user-1", resultOk, "test-user-1"},
		{"no params, accept-all default", "", resultOk, "legacy-test-user"},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodGet, "/auth"+c.query, nil)
			rec := httptest.NewRecorder()

			handleAuth(rec, req)

			var got authResponse
			if err := json.NewDecoder(rec.Body).Decode(&got); err != nil {
				t.Fatalf("decode response: %v", err)
			}
			if got.ResultCode != c.wantResult {
				t.Errorf("ResultCode = %d, want %d", got.ResultCode, c.wantResult)
			}
			if got.UserId != c.wantUserId {
				t.Errorf("UserId = %q, want %q", got.UserId, c.wantUserId)
			}
		})
	}
}
