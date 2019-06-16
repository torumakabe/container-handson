package main

import (
	"context"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"

	"github.com/Azure/azure-sdk-for-go/services/keyvault/auth"
	"github.com/Azure/azure-sdk-for-go/services/keyvault/2016-10-01/keyvault"
)

func getKeyvaultSecret(w http.ResponseWriter, r *http.Request) {
	authorizer, err := auth.NewAuthorizerFromEnvironment()
	if err != nil {
		log.Printf("unable to get your authorizer object: %v", err)
		return
	}

	keyClient := keyvault.New()
	keyClient.Authorizer = authorizer

	keyvaultName := os.Getenv("AZURE_KEYVAULT_NAME")
	keyvaultSecretName := os.Getenv("AZURE_KEYVAULT_SECRET_NAME")
	keyvaultSecretVersion := os.Getenv("AZURE_KEYVAULT_SECRET_VERSION")

	secret, err := keyClient.GetSecret(context.Background(), fmt.Sprintf("https://%s.vault.azure.net", keyvaultName), keyvaultSecretName, keyvaultSecretVersion)
	if err != nil {
		log.Printf("unable to get your Keyvault secret: %v", err)
		return
	}

	io.WriteString(w, fmt.Sprintf("Can I tell you my awesome dad joke?: %v", *secret.Value))
}

func main() {
	http.HandleFunc("/", getKeyvaultSecret)
	http.ListenAndServe(":8080", nil)
}
