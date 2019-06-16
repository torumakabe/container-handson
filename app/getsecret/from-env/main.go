package main

import (
	"fmt"
	"io"
	"net/http"
	"os"
)

func getSecret(w http.ResponseWriter, r *http.Request) {
	secret := os.Getenv("SECRET_JOKE")

	io.WriteString(w, fmt.Sprintf("Can I tell you my awesome dad joke?: %v", secret))
}

func main() {
	http.HandleFunc("/", getSecret)
	http.ListenAndServe(":8080", nil)
}
