# NextCloud com SSL e Docker
Caso esteja com dúvidas, preparamos um vídeo explicando os passos abaixo para facilitar a compreensão. 
[`Vídeo de instalação`](https://www.youtube.com/watch?v=48rYcegMWgc)

## Instalando o Docker
Você precisa ter, em seu servidor, o Docker instalado. A instalação pode ser feita com um script oficial, seguindo os seguintes passos:
- 1º: Baixar o docker
```bash
curl -fsSL https://get.docker.com -o get-docker.sh
```
- 2º: Executar o script
```bash
sh get-docker.sh
```
- 3º: Dar permissões para executar o comando docker ao seu usuário
```bash
sudo usermod -aG docker $USER
```
- 4º: Remover o script de instalação
```bash
rm get-docker.sh
```

## Alterações antes de rodar pela primeira vez

- 1º: Copie o arquivo `.env.example` para `.env` e altere os valores das variáveis de ambiente.

| Ambiente | Serviço | 
|-------------|---------|
| [`VIRTUAL_HOST`](https://github.com/nginx-proxy/nginx-proxy#usage) | `web` |
| [`LETSENCRYPT_HOST`](https://github.com/nginx-proxy/docker-letsencrypt-nginx-proxy-companion/blob/master/docs/Basic-usage.md#step-3---proxyed-containers) | `web` |
| [`LETSENCRYPT_EMAIL`](https://github.com/nginx-proxy/docker-letsencrypt-nginx-proxy-companion/blob/master/docs/Let's-Encrypt-and-ACME.md#contact-address) | `web` |
| `POSTGRES_PASSWORD` | `db` |

> **PS**: O Let's Encrypt somente funciona em servidores quando `VIRTUAL_HOST` e `LETSENCRYPT_HOST` possuirem um domínio público válido registrado em um servidor DNS. Não tente utilizar localhost, não irá funcionar!

- 2º: Crie uma rede utilizando o seguinte comando:
```bash
docker network create reverse-proxy
```

## Colocando em execução
Para o seu ambiente funcionar, utilize os seguintes comandos:
```bash
docker-compose up -d
docker-compose -f docker-compose.proxy.yml up -d
```

## Configuração WEB
Com o docker configurado e executando, agora vamos acessar o domínio definido e terminarmos a configuração. 

Não iremos alterar a pasta de destino, escolheremos o banco PostgreSQL e iremos colocar as informações:

- Nome do banco: nextcloud
- Senha do banco: senha definida no .env
- Usuário do banco: nextcloud
- Endereço do banco: db

Agora basta clicarmos em concluir configurações e aguardar.

## Após a instalação
Após terminado, abra a seguinte url https://SEU-DOMINIO/settings/admin/overview


Caso seja necessário rodar algum comando `occ`, utilize os seguintes comandos:

```bash
docker-compose exec -u www-data app ./occ db:add-missing-indices
docker-compose exec -u www-data app ./occ db:convert-filecache-bigint
```
> **OBS**: app é o nome do seu container. Para listar os containers, utilize o comando ```docker-compose ps```

## Configurações personalizadas do PHP

Caso você precisar alterar alguma configuração do PHP, acesse o seguinte arquivo [`.docker/app/config/php.ini`](/.docker/app/config/php.ini).


## Utilizando uma versão específica do Nextcloud

Altere o  [Dockerfile](/.docker/app/Dockerfile#L1) na linha de número 1 e coloque a versão desejada.

Construa as imagens e levante o container novamente:

```bash
docker-compose build
docker-compose down
docker-compose up -d
```

Caso quiser ver as alterações, rode:
```bash
docker-compose logs -ft
```
Você verá a seguinte mensagem nos logs, além de outras várias mensagens de upgrade:

```
app_1      | 2020-04-28T19:49:38.568623133Z Initializing nextcloud 18.0.4.2 ...
app_1      | 2020-04-28T19:49:38.577733913Z Upgrading nextcloud from 18.0.3.0 ...
```
