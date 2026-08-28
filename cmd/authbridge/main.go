// Command authbridge is OpenPak's Photon custom-authentication webhook for
// the Outbound proof of concept. Photon Cloud calls this over HTTP with the
// client's AuthenticationValues.Parameters as query/form values and expects
// a JSON verdict back. See:
// https://doc.photonengine.com/realtime/v5/connection-and-authentication/authentication/custom-authentication
//
// PROOF-OF-CONCEPT ONLY. It accepts any "identity" value as authenticated —
// there is no OpenPak session verification yet. Never point a Photon app's
// Custom Authentication URL at this without adding real verification first,
// and never forward a Nintendo/OpenPak token here (see HANDOFF.md).
package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
)

type authResponse struct {
	ResultCode int    `json:"ResultCode"`
	UserId     string `json:"UserId,omitempty"`
	Nickname   string `json:"Nickname,omitempty"`
	Message    string `json:"Message,omitempty"`
}

const (
	resultOk     = 1
	resultFailed = 2
)

func handleAuth(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseForm(); err != nil {
		http.Error(w, "bad request", http.StatusBadRequest)
		return
	}

	// ponytail: identity is taken as already-stable and used verbatim as the
	// Photon UserId. Swap for real OpenPak session-token verification before
	// this ever sees production or non-test traffic.
	identity := r.Form.Get("identity")
	w.Header().Set("Content-Type", "application/json")
	if identity == "" {
		json.NewEncoder(w).Encode(authResponse{
			ResultCode: resultFailed,
			Message:    "missing identity parameter",
		})
		return
	}

	json.NewEncoder(w).Encode(authResponse{
		ResultCode: resultOk,
		UserId:     identity,
		Nickname:   r.Form.Get("nickname"),
	})
}

func main() {
	addr := os.Getenv("AUTHBRIDGE_ADDR")
	if addr == "" {
		addr = ":8081"
	}
	http.HandleFunc("/auth", handleAuth)
	log.Printf("authbridge listening on %s (proof-of-concept, no real verification)", addr)
	log.Fatal(http.ListenAndServe(addr, nil))
}
