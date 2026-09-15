# Verificação do M4a — Key Vault sem senha

Prova que um pod consegue ler um segredo do Key Vault usando **workload
identity**, sem que exista senha alguma no cluster, no Git ou num Secret do
Kubernetes.

Nada deste diretório é sincronizado pelo Argo CD. Aplique à mão, confira,
apague.

## Pré-requisitos

O `terraform apply` do M4a precisa ter rodado (ele liga o emissor OIDC do
cluster, o addon do CSI driver, cria a identidade e libera o Key Vault para a
sub-rede privada). Cluster ligado.

## 1. Colocar um segredo no cofre

O segredo tem uma origem inevitavelmente manual — alguém precisa criar o token
no GitHub e guardá-lo. O que a workload identity elimina não é esse passo, é
tudo o que vinha depois dele: copiar para um YAML, comitar, rotacionar à mão.

Crie um Personal Access Token em **GitHub → Settings → Developer settings →
Personal access tokens**, com escopo `repo` (o Backstage vai criar
repositórios no M4c). Depois:

```powershell
$kv = az keyvault list -g azpe-dev-rg --query "[0].name" -o tsv
az keyvault secret set --vault-name $kv --name github-token --value "COLE_O_TOKEN_AQUI"
```

Se esse comando falhar com erro de rede, é o firewall do Key Vault fazendo o
trabalho dele: o `default_action` é `Deny` e a sua máquina não está na lista.
Libere o seu IP temporariamente e remova depois:

```powershell
$meuIp = (Invoke-RestMethod https://api.ipify.org?format=json).ip
az keyvault network-rule add --name $kv -g azpe-dev-rg --ip-address $meuIp
# ... rode o `secret set` ...
az keyvault network-rule remove --name $kv -g azpe-dev-rg --ip-address $meuIp
```

## 2. Aplicar os manifestos

O arquivo `manifests.yaml` tem marcadores no lugar dos identificadores reais.
Este bloco busca os valores no Azure e aplica sem você editar nada à mão:

```powershell
$clientId = az identity show -g azpe-dev-rg -n azpe-dev-backstage-identity --query clientId -o tsv
$kv = az keyvault list -g azpe-dev-rg --query "[0].name" -o tsv

(Get-Content gitops/verify/keyvault/manifests.yaml) `
  -replace 'REPLACE_CLIENT_ID', $clientId `
  -replace 'REPLACE_KEYVAULT_NAME', $kv | kubectl apply -f -
```

## 3. Conferir

```powershell
kubectl -n backstage logs kv-test
```

O esperado:

```
--- segredo montado como arquivo ---
...
bytes lidos: 93
OK: o pod leu o Key Vault sem nenhuma senha no cluster.
```

O log mostra o tamanho, nunca o conteúdo. Provar que a leitura funcionou não
exige expor o segredo no log.

## Se falhar

| Sintoma | Causa provável |
|---|---|
| Pod em `ContainerCreating` por mais de 1 min | O CSI driver não conseguiu montar. `kubectl -n backstage describe pod kv-test` mostra o erro real nos Events. |
| `no matching federated identity record found` | O `subject` não bate. Ele é `system:serviceaccount:backstage:backstage` e é comparado como string exata — confira namespace e nome da ServiceAccount contra o que está em `environments/dev/main.tf`. |
| `403 Forbidden` do Key Vault | Ou a role `Key Vault Secrets User` ainda não propagou (espere alguns minutos), ou a sub-rede não está liberada no `network_acls` do cofre. |
| `SecretNotFound` | O segredo `github-token` não existe no cofre. Volte ao passo 1. |

## 4. Limpar

```powershell
kubectl -n backstage delete pod kv-test
```

O namespace, a ServiceAccount e o SecretProviderClass ficam — o M4b vai usá-los
para o Backstage de verdade.
