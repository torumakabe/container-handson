package main

import (
	"fmt"
	"io"
	"io/ioutil"
	"log"
	"net/http"
)

func getSecret(w http.ResponseWriter, r *http.Request) {
	secret, err := ioutil.ReadFile("/kvmnt/joke")
	if err != nil {
		log.Printf("unable to read your secret file: %v", err)
		return
	}

	io.WriteString(w, fmt.Sprintf("Can I tell you my awesome dad joke?: %v", string(secret)))
}

func main() {
	http.HandleFunc("/", getSecret)
	http.ListenAndServe(":8080", nil)
}
