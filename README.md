# azure-platform-engineering

Projeto flagship do roteiro de platform engineering (catálogo pessoal p47),
adaptado para Azure. Objetivo final: um Internal Developer Platform (IDP)
onde um desenvolvedor pede "nova API" no Backstage e a plataforma cuida de
repositório, infraestrutura, CI/CD, deploy, observabilidade e segurança —
sem ele precisar entender o que tem por baixo.

Este README documenta o **Milestone 1: landing zone** — a base de rede,
identidade e segredo sobre a qual todo o resto (AKS, GitOps, Backstage,
Crossplane) vai se apoiar. Ele é longo de propósito: a ideia não é só você
rodar os comandos, é você conseguir explicar cada decisão numa entrevista.

## A regra de sempre

Igual nos 5 repositórios anteriores: nada aqui conta como pronto só porque
o `terraform plan` "parece certo". Só conta quando um `terraform apply`
real, contra uma subscription Azure real, criou os recursos e o pipeline
de CI ficou verde de verdade.

## Arquitetura deste milestone

```
bootstrap/              ← roda 1x, local, manualmente por você
  └─ cria: resource group + storage account (backend remoto do Terraform)
           + App Registration com federated credential (identidade OIDC)
           + role assignments dessa identidade

modules/landing-zone/   ← módulo reutilizável
  └─ resource group + VNet (sub-rede pública/privada + NSGs)
           + Log Analytics Workspace + Key Vault

environments/dev/       ← instancia o módulo acima, com backend remoto
  └─ é isto que o GitHub Actions roda a cada PR/push

.github/workflows/
  terraform.yml         ← plan em toda PR, apply gated (aprovação manual)
                           só em push na main
```

## Por que existe um `bootstrap/` separado

Terraform guarda seu estado (o "state") em algum lugar — por padrão, num
arquivo local. Isso não escala: se dois PRs rodarem `terraform apply` ao
mesmo tempo, ou se você perder o laptop, o estado se perde ou corrompe.
A solução padrão é um **backend remoto** (aqui, um Storage Account do
Azure) com **locking** — enquanto um `apply` está rodando, outro não
consegue começar contra o mesmo state.

Só que isso cria um problema clássico do ovo e da galinha: para o
`environments/dev` usar um backend remoto, o Storage Account desse backend
precisa **já existir**. E para o GitHub Actions rodar `terraform apply`
sem um secret estático guardado manualmente, a identidade OIDC dele
(explicado abaixo) também precisa já existir. Nenhuma das duas coisas pode
nascer de dentro do pipeline que elas mesmas vão sustentar.

`bootstrap/` resolve isso rodando **uma única vez, localmente, com state
local** (nunca remoto — veja o comentário em `bootstrap/versions.tf`). É
o único lugar deste projeto que usa sua identidade pessoal do Azure
diretamente, e o único Terraform aqui que você aplica com a mão, sem
passar por CI. Depois disso, tudo o mais passa a rodar via pipeline.

**Pergunta de entrevista que isso responde:** *"Como você provisiona a
própria infraestrutura que guarda o state do Terraform?"* — resposta: com
um bootstrap separado, de state local, executado uma única vez fora do
pipeline principal.

## Por que OIDC/federated identity em vez de um secret

O jeito antigo de dar ao GitHub Actions acesso ao Azure era criar um
service principal, gerar um **client secret** (uma senha, basicamente),
colar ela nos GitHub Secrets, e lembrar de rotacionar antes dela expirar.
Isso é um segredo de longa duração guardado fora do Azure — exatamente o
tipo de coisa que vaza em log, em captura de tela, em repositório errado.

Com **OIDC (OpenID Connect) federado**, não existe segredo nenhum
guardado. A cada execução do workflow, o GitHub emite um token JWT de
curtíssima duração, assinado por ele mesmo, dizendo "eu sou a execução X
do repositório Y, disparada por este evento". O Azure AD tem uma
**federated identity credential** que diz "eu confio em tokens assinados
pelo GitHub que afirmem ser exatamente este repositório, neste contexto".
Se o token bater com essa condição, o Azure AD troca ele por um access
token de verdade, válido por pouco tempo. Não há nada para vazar porque
não há nada de longa duração para vazar.

### O formato do `subject` (onde este projeto sangrou)

O `subject` (claim `sub`) que o GitHub emite **não** é o óbvio
`repo:owner/repo:contexto`. Ele embute IDs numéricos imutáveis:

```
repo:Pmacoy@42946356/azure-platform-engineering@1370531818:ref:refs/heads/main
     └─ login ─┘ └ ID da conta ┘ └── nome do repo ──┘ └ ID do repo ┘
```

O motivo é defensivo: nomes de conta e de repositório podem ser
renomeados, deletados e re-registrados por outra pessoa. Se a confiança
no Azure estivesse ancorada só no texto `Pmacoy/azure-platform-engineering`,
quem registrasse esse nome depois de você abandoná-lo herdaria acesso à
sua subscription. IDs numéricos nunca são reaproveitados, então ancorar
neles fecha esse buraco.

Duas armadilhas que derrubaram o primeiro push deste projeto, ambas com a
**mesma** mensagem de erro genérica (`AADSTS700213`):

1. **Capitalização.** O Azure AD compara o subject como string exata e
   case-sensitive. `pmacoy` ≠ `Pmacoy`, mesmo que URLs do GitHub
   funcionem em qualquer caixa.
2. **Os IDs numéricos.** Cadastrar `repo:Pmacoy/azure-platform-engineering:...`
   (o formato que aparece na maioria dos tutoriais antigos) nunca vai
   casar com o que o GitHub realmente envia hoje.

O jeito de diagnosticar os dois é o mesmo, e é o que vale levar pra
entrevista: **a mensagem de erro do Azure cita o subject apresentado**.
Compare ele caractere a caractere com o que está cadastrado, em vez de
sair procurando problema de permissão.

Repare que este projeto usa **três** federated credentials com escopos
diferentes:

1. Qualquer pull request (`...:pull_request`) — usada só pelo job de
   `plan` quando ele roda a partir de uma PR. Só dá plan, nunca apply.
2. O GitHub Environment `production` (`...:environment:production`) —
   usada só pelo job de `apply`, e só depois de alguém aprovar
   manualmente.
3. Push direto na branch `main` (`...:ref:refs/heads/main`) — usada pelo
   job de `plan` quando ele roda a partir de um push direto (sem PR), que
   é exatamente o que acontece aqui, já que o `apply` depende do `plan`
   ter rodado no mesmo push. Sem esta terceira credencial, um push direto
   na main não consegue autenticar nem pra fazer plan.

O prefixo das três (`repo:<owner>@<id>/<repo>@<id>`) é montado uma vez só,
em `local.github_oidc_subject_prefix` no `bootstrap/main.tf` — se um dia
os IDs mudarem (repositório transferido de conta, por exemplo), é um lugar
só para corrigir, não três.

Cada uma dessas é mais estrita do que confiar em "qualquer coisa deste
repositório": uma PR aberta por qualquer pessoa só consegue plan; só um
push que já está na `main` consegue disparar um plan que vira apply; e o
apply em si só roda depois de aprovação manual do Environment.

**Pergunta de entrevista que isso responde:** *"Como o seu pipeline se
autentica no provedor de nuvem sem guardar uma senha?"* — e também *"como
você reduz ainda mais o blast radius de uma credencial de CI comprometida?"*

## Por que a landing zone é um módulo, não código solto

O `environments/dev/main.tf` não define um único `azurerm_resource_group`
ou `azurerm_virtual_network` diretamente — ele **chama**
`modules/landing-zone`. Essa é a mesma lição da Fase 02 do roteiro: se um
dia existir `environments/staging` ou `environments/prod`, eles reusam o
mesmo módulo com parâmetros diferentes, em vez de cada ambiente reescrever
a mesma VNet do zero de um jeito ligeiramente diferente. O módulo já
carrega os padrões da "organização" embutidos — Key Vault sempre com
`purge_protection_enabled = true`, sub-rede privada sempre negando
internet por padrão — para que usar errado seja mais difícil que usar
certo.

## Decisões específicas que valem explicar numa entrevista

- **`shared_access_key_enabled = false` no storage account de estado** —
  desliga a chave de acesso estática por completo. A única forma de ler
  ou escrever o tfstate é com uma identidade do Azure AD autorizada por
  role assignment (`use_azuread_auth = true` no backend). Sem isso, a
  chave estática seria, de novo, um segredo de longa duração.
- **`enable_rbac_authorization = true` no Key Vault** — acesso ao Key
  Vault controlado pelo mesmo sistema de roles do resto do Azure, em vez
  de uma lista de "access policies" separada e fácil de esquecer de
  manter sincronizada.
- **`network_acls { default_action = "Deny" }` no Key Vault** — o
  pipeline de CI roda fora da rede do Azure (runners hospedados pela
  GitHub), então ele não consegue falar com o *plano de dados* deste Key
  Vault ainda (ler/escrever segredos) — só com o *plano de controle*
  (criar/configurar o recurso via Terraform, que é uma chamada ao Azure
  Resource Manager, não ao Key Vault em si). Isso é esperado agora; a
  Fase 06 vai conectar uma rota real quando isso importar.
- **Contributor na assinatura inteira para a identidade do GitHub
  Actions** — deliberadamente amplo demais para uma plataforma madura, e
  documentado assim de propósito no próprio `bootstrap/main.tf`. É o
  ponto de partida realista de um projeto pessoal. Apertar isso
  (escopo por resource group, Azure Policy, PIM) é trabalho explícito do
  Milestone 5 (guardrails), não um erro deste milestone.

## Passo a passo para rodar isso de verdade

### 0. Pré-requisitos

- Azure CLI instalado (`az --version`) e uma subscription à qual você tem
  acesso de Owner (ou Contributor + User Access Administrator — precisa
  poder criar role assignments).
- Terraform ou OpenTofu instalado localmente.
- Um repositório GitHub vazio chamado `azure-platform-engineering`
  (criado por você, sem README/gitignore automático, para não conflitar
  com o push deste código).

### 1. Ajustar o nome real do repositório

Edite `bootstrap/variables.tf` e troque o `default` de `github_repository`
pelo seu usuário/organização real no GitHub, exatamente no formato
`dono/repositorio`. As federated credentials são validadas por esse
texto exato — um caractere errado aqui, e o GitHub Actions recebe
"AADSTS70021: No matching federated identity record found" mais tarde.

### 2. Login e bootstrap

```bash
az login
az account show   # confirme que é a subscription certa

cd bootstrap
terraform init
terraform plan     # leia antes de aplicar
terraform apply
```

Guarde a saída — os 6 outputs (`state_resource_group_name`,
`state_storage_account_name`, `state_container_name`, `azure_client_id`,
`azure_tenant_id`, `azure_subscription_id`) são exatamente o que entra
nos GitHub Secrets no próximo passo. Para ver de novo sem reaplicar:
`terraform output`.

### 3. GitHub Secrets

No repositório, em Settings → Secrets and variables → Actions, crie:

| Secret               | Valor (do output do bootstrap) |
|-----------------------|---------------------------------|
| `AZURE_CLIENT_ID`      | `azure_client_id` |
| `AZURE_TENANT_ID`      | `azure_tenant_id` |
| `AZURE_SUBSCRIPTION_ID`| `azure_subscription_id` |
| `TF_STATE_RG`          | `state_resource_group_name` |
| `TF_STATE_SA`          | `state_storage_account_name` |

### 4. GitHub Environment com aprovação manual

Em Settings → Environments → New environment, crie um chamado exatamente
`production` (tem que bater com `var.github_environment` do bootstrap e
com o `environment:` do job `apply` no workflow). Em "Required reviewers",
adicione você mesmo. É isso que faz o job de apply parar e esperar um
clique antes de tocar no Azure de verdade — o mesmo padrão que o
`secure-cicd-pipeline` já usa antes de deploy.

### 5. Primeiro push

```bash
git init -b main
git add .
git commit -m "M1: bootstrap OIDC + landing zone (VNet, NSGs, Log Analytics, Key Vault)"
git remote add origin https://github.com/<seu-usuario>/azure-platform-engineering.git
git push -u origin main
```

O push direto na `main` já dispara o job `plan` (sem aplicar nada). Abra
uma branch e um PR se quiser ver o resumo do plano antes — o job escreve
o `terraform plan` inteiro no resumo da execução (Summary), sem precisar
abrir logs.

### 6. Aprovar o apply

Depois do plan rodar verde no push da `main`, o job `apply` fica
"Waiting" até você aprovar em Actions → a execução → Review deployments.
Só depois disso o `terraform apply` de verdade roda contra o Azure.

## Se (quando) alguma coisa falhar

Sem exceção nos 5 projetos anteriores, o primeiro push real bateu em pelo
menos um erro que só aparece rodando contra a coisa real. Aqui não deveria
ser diferente — prováveis suspeitos, na ordem mais provável:

1. **`AADSTS70021` no login do provider** — o texto de `github_repository`
   no bootstrap não bate byte a byte com o repositório real, ou a branch/
   environment usada no push não bate com o `subject` da federated
   credential.
2. **Erro de permissão ao gravar o state** — a role assignment de
   `Storage Blob Data Contributor` na identidade do GitHub Actions ainda
   não propagou (o Azure AD às vezes leva alguns minutos) ou o
   `use_azuread_auth = true` está faltando em algum `-backend-config`.
3. **Nome do Key Vault ou do Storage Account já em uso** — os dois
   precisam ser únicos *globalmente* no Azure inteiro, não só na sua
   assinatura; o sufixo aleatório existe por causa disso, mas colisão
   ainda é possível.

Cole o log real do job que falhar e resolvemos como sempre: causa raiz
antes de correção, correção verificada no próximo push real.

## Próximos milestones

| # | Escopo |
|---|--------|
| M2 | AKS + Azure Container Registry via módulo reutilizável |
| M3 | GitOps com Argo CD + pipeline reutilizável publicando no ACR |
| M4 | Golden path no Backstage ("criar nova API") |
| M5 | Guardrails — Crossplane Composition + Azure Policy |
| M6 | Observabilidade — Azure Monitor + Managed Grafana |
| M7 | Decisões de arquitetura documentadas |
