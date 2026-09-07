// Command authbridge is OpenPak's Photon custom-authentication webhook for
// the Outbound proof of concept. Photon Cloud calls this over HTTP with the
// client's AuthenticationValues.Parameters as query/form values and expects
// a JSON verdict back. See:
// https://doc.photonengine.com/realtime/v5/connection-and-authentication/authentication/custom-authentication
//
// PROOF-OF-CONCEPT ONLY. It currently accepts every request as authenticated
// — there is no OpenPak session verification yet, and Outbound's real
// custom-auth parameter names aren't known yet either. Never point a Photon
// app's Custom Authentication URL at this without adding real verification
// first. Parameter values are never logged, only their names, in case
// Outbound resends BAAS-token-shaped data (see HANDOFF.md).
package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
	"sort"
	"strings"
)

type authResponse struct {
	ResultCode int    `json:"ResultCode"`
	UserId     string `json:"UserId,omitempty"`
	Nickname   string `json:"Nickname,omitempty"`
	Message    string `json:"Message,omitempty"`
}

const resultOk = 1

func paramNames(form map[string][]string) string {
	names := make([]string, 0, len(form))
	for k := range form {
		names = append(names, k)
	}
	sort.Strings(names)
	return strings.Join(names, ",")
}

func handleAuth(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseForm(); err != nil {
		http.Error(w, "bad request", http.StatusBadRequest)
		return
	}

	// ponytail: accept-all so the first live test just proves the Name
	// Server -> Master Server -> Game Server flow and custom-auth wiring
	// work at all. Add real OpenPak identity mapping and rejection once
	// Outbound's actual parameter names are known from this endpoint's logs.
	log.Printf("auth request, params=[%s]", paramNames(r.Form))

	identity := r.Form.Get("identity")
	if identity == "" {
		identity = "openpak-test-user"
	}
	w.Header().Set("Content-Type", "application/json")
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
