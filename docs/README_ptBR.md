# Nextcloud com Docker

[English](../README.md)

Um ambiente Docker configurável para organizações e equipes que hospedam seu próprio Nextcloud. Mantido pela [LibreCode](https://librecode.coop/), este repositório reúne a aplicação, o servidor web, o cache e a integração com banco de dados em uma implantação que pode ser adaptada à sua infraestrutura.

## Por que utilizar este projeto?

- **Controle das atualizações.** Escolha uma versão principal do Nextcloud e planeje as migrações sem mudanças inesperadas de versão.
- **Flexibilidade na infraestrutura.** Utilize Docker Compose com Nginx, Redis, PostgreSQL e armazenamento opcional no Garage S3.
- **Imagens com verificações automatizadas.** As imagens publicadas acompanham versões mantidas do Nextcloud e passam por varredura de vulnerabilidades e testes de execução antes da publicação.
- **Separação entre produção e desenvolvimento.** Imagens estáveis versionadas e o canal `master-fpm` atendem a necessidades diferentes.

O projeto é voltado a equipes que administram sua própria infraestrutura ou oferecem Nextcloud como serviço. Ele fornece ferramentas de implantação, não uma assinatura de hospedagem.

## Comece a utilizar

Você precisa do Docker Engine com Docker Compose, de um domínio para acesso público e de um proxy reverso. O exemplo utiliza o [proxy Nginx da LibreCode](https://github.com/LibreCodeCoop/nginx-proxy); a extensão Compose do PostgreSQL está incluída neste repositório.

```bash
cp .env.example .env
# Edite .env: domínio, credenciais, administrador e versão do Nextcloud.
docker network create reverse-proxy
docker network create postgres
docker compose -f docker-compose.yml -f docker-compose-postgres.yml up -d --build
```

O proxy reverso deve estar configurado e conectado à rede externa `reverse-proxy`. Configure também o DNS antes de esperar que o HTTPS funcione. Em produção, revise a versão do PostgreSQL usada no exemplo, os backups e as migrações dos volumes.

Para variáveis de ambiente, instalações existentes, armazenamento e solução de problemas, consulte o [guia de implantação](deployment_ptBR.md).

## Versões e atualizações do Nextcloud

Defina `NEXTCLOUD_VERSION` no arquivo `.env` para selecionar a **imagem-base oficial do Nextcloud** utilizada no build local do Docker Compose. Isso é diferente da publicação das imagens da LibreCode no GHCR.

As imagens de aplicação da LibreCode disponibilizam tags por versão, por exemplo:

```text
ghcr.io/librecodecoop/nextcloud-docker-app:35-fpm
```

Em produção, **fixe uma versão principal ou o digest OCI** e planeje cada atualização de versão principal. As tags móveis `:latest` e `:stable-fpm` podem passar para uma versão principal mais recente; não são uma boa escolha para atualizações automáticas em produção.

Consulte [imagens, tags e política de atualização](images.md) para conhecer as opções.

## Documentação

| Guia | Conteúdo |
| --- | --- |
| [Implantação e personalização](deployment_ptBR.md) | Instalação, configuração, armazenamento, PHP e logs |
| [Imagens de contêiner](images.md) | Tags, compatibilidade e atualizações seguras |
| [Nextcloud Talk](https://github.com/LibreCodeCoop/nextcloud-docker-talk) | Serviços adicionais para o Talk |
| [Comandos de desenvolvimento](ncdd.md) | Interface `bin/ncdd` para desenvolvimento local |
| [Manutenção das imagens](maintenance.md) | Descoberta de versões, workflows, CI e publicação |
