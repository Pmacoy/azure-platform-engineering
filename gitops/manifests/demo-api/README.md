# manifests/demo-api

Estado desejado da aplicação `demo-api`. O Argo CD sincroniza este diretório
e aplica o resultado no cluster.

## Por que esta explicação está aqui e não no `kustomization.yaml`

Ela estava lá. O `kustomize edit set image`, que o pipeline roda a cada build,
não faz edição de texto — ele carrega o YAML, altera a estrutura e reescreve o
arquivo inteiro pelo próprio serializador. Serializador de YAML **descarta
comentários**, então o primeiro build apagou tudo que estava escrito ali.

Foi visível no diff do commit do bot: seis linhas alteradas para uma mudança
de uma tag. Vale como regra geral — **arquivo que uma ferramenta reescreve não
é lugar para documentação**.

## O `kustomization.yaml` é a junta entre o pipeline e o GitOps

O `deployment.yaml` referencia a imagem apenas como `demo-api`. O bloco
`images:` do `kustomization.yaml` transforma esse nome no endereço real do
ACR mais a tag do commit, e é exatamente esse bloco que o
`.github/workflows/build.yml` edita e commita a cada build.

O efeito prático:

- **O estado desejado está no Git, sempre.**
  `git log gitops/manifests/demo-api/kustomization.yaml` responde "o que estava
  rodando no dia X" sem consultar o cluster.
- **Reverter um deploy é `git revert`**, não um comando imperativo que alguém
  precisa lembrar de rodar sob pressão.
- **O CI não precisa de credencial do cluster.** Ele altera um arquivo e vai
  embora; quem aplica é o Argo CD, de dentro, puxando.

O endereço do registry está fixo no arquivo porque o Terraform o gerou com
sufixo aleatório (nomes de ACR são únicos globalmente no Azure). É o ponto de
contato inevitável entre a camada que provisiona e a camada que declara.

## Detalhe que quebrou o primeiro deploy

O `deployment.yaml` pede `runAsNonRoot: true` **e** declara `runAsUser: 65532`.
O segundo não é redundância.

O kubelet precisa *provar* que o usuário não é root antes de iniciar o
container. Se a imagem declara `USER nonroot` — um nome — ele teria que abrir
a imagem e resolver esse nome, e numa imagem distroless não há o que resolver.
Sem conseguir verificar, ele recusa, e o pod fica em
`CreateContainerConfigError` sem nunca ter tentado executar a imagem.

`65532` é o UID do usuário `nonroot` das imagens distroless do Google. O
`Dockerfile` também foi corrigido para usar o número, de modo que a imagem se
descreva sozinha sob qualquer política que exija usuário não-root.
