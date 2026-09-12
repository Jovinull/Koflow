# Koflow

### O processo pode parar. O trabalho continua registrado.

[![CI](https://github.com/Jovinull/Koflow/actions/workflows/ci.yml/badge.svg)](https://github.com/Jovinull/Koflow/actions/workflows/ci.yml)
[![Kof](https://img.shields.io/badge/Kof-0.3.22--beta-7c3aed)](https://github.com/KofLang/Kof4j)
![Backend](https://img.shields.io/badge/backend-JVM-2563eb)
![SQLite](https://img.shields.io/badge/storage-SQLite-003b57)
![Status](https://img.shields.io/badge/status-experimental-d97706)

**Runtime de execução durável e orquestração, escrito em [Kof](https://github.com/KofLang/Kof4j).**

Envie o trabalho para depois, execute em outro processo e mantenha seu estado salvo.
O problema que o Koflow resolve não é enfileirar chamadas: é manter a execução íntegra
quando o processo morre no meio dela. O estado de execução vive em SQLite, as tentativas
são contadas e uma execução interrompida volta a ficar disponível.

A Kof oferece as primitives da linguagem; o Koflow acrescenta a camada acima delas —
semântica de execução, estado durável, recuperação e coordenação entre processos.

Hoje o runtime roda embutido na própria aplicação, no alvo JVM, e entrega a primeira
camada dessa proposta: jobs persistentes com concessão, tentativas limitadas e
recuperação após interrupção. É uma base para tarefas como gerar relatórios, processar
arquivos e integrar serviços fora da requisição principal. Runtime, exemplos e
asserções são escritos em Kof.

## O que já funciona

- **Persistência:** jobs e payloads sobrevivem ao encerramento do processo.
- **Histórico durável:** cada tentativa fica registrada com início, fim, resultado e erro.
- **Retries com espera:** uma falha agenda a próxima tentativa com atraso crescente.
- **Execução pontual futura:** um job pode ser enfileirado para não rodar antes de um instante.
- **Recuperação:** uma execução interrompida volta a ficar disponível após expirar seu prazo.
- **Controle de posse:** confirmações de tentativas antigas são rejeitadas.
- **Inspeção:** consulte o estado atual e a sequência de tentativas pelo ID do job.

O projeto é **experimental**. A recuperação foi testada com `SIGKILL` e a disputa
por um job foi exercitada entre oito processos, nos dois ambientes validados.
Efeitos externos podem se repetir; handlers devem ser idempotentes.
Veja o [contrato de execução](#contrato-de-execução).

## Estado e direção

| Estágio | Conteúdo |
| --- | --- |
| **Hoje** | Jobs persistentes locais: enqueue imediato ou para um instante futuro, concessão de execução, retries com espera crescente, histórico durável das tentativas, recuperação após crash e disputa entre processos. Experimental. |
| **Próximo** | Filas explícitas e ciclo de vida de workers. Planejado, ainda não implementado. |
| **Direção** | Workflows e DAGs, ferramental de operação e workers remotos. |

Apenas a linha "Hoje" existe no código. As demais indicam para onde o runtime cresce,
não o que ele já faz.

## Comece por aqui

Ambientes validados: Linux x86_64 e Windows 11 x86_64 no Git Bash, ambos com
Kof 0.3.22-beta/JVM, JDK 21 e SQLite JDBC 3.53.4.0. Os scripts precisam de Bash, curl,
tar e coreutils; os testes também usam `rg` (ripgrep) com suporte a `--crlf`. O bootstrap
automático é específico de Linux: ele baixa versões fixas, confere SHA-256 e instala em
`${XDG_CACHE_HOME:-$HOME/.cache}/koflow`. A distribuição Kof inclui o JDK.

### Linux

```sh
git clone https://github.com/Jovinull/Koflow.git
cd Koflow
make bootstrap
make build
make test
make demo
```

### Windows

`make bootstrap` exige Linux x86_64 e o Git for Windows não inclui `make`. No Windows a
instalação é manual, com a distribuição `windows-x86_64`, e os scripts são chamados
diretamente pelo Bash. Execute tudo no **Git Bash**, a partir da raiz do repositório.

A instalação roda em um subshell com `set -e`, e a configuração e a execução só acontecem
se ele terminar bem: uma instalação malsucedida não passa a usar em silêncio um cache
anterior. O subshell fica isolado de propósito — dentro de uma lista `&&` o `set -e` é
ignorado, e a verificação deixaria de interromper a sequência. Os `export` ficam na sessão,
não no subshell, para que você possa repetir `bash scripts/test.sh` depois sem
reconfigurar nada.

```sh
cache="$HOME/.cache/koflow"
base=https://github.com/KofLang/Kof4j/releases/download/kof-0.3.22-beta-windows-x86_64
jdbc=https://repo.maven.apache.org/maven2/org/xerial/sqlite-jdbc/3.53.4.0
jar_sha=bcb1f51e36f940867e83342f9efbf5968ac44a6bef4d397bb4af7b17b45cd2fb

(
    set -e
    tmp="$(mktemp -d)"
    trap 'rm -rf -- "$tmp"' EXIT
    mkdir -p "$cache"
    curl -fL -o "$tmp/SHA256SUMS" "$base/SHA256SUMS"
    curl -fL -o "$tmp/kof-0.3.22-beta-windows-x86_64.zip" "$base/kof-0.3.22-beta-windows-x86_64.zip"
    cd "$tmp"
    sha256sum -c SHA256SUMS
    curl -fL -o sqlite-jdbc-3.53.4.0.jar "$jdbc/sqlite-jdbc-3.53.4.0.jar"
    printf '%s  %s\n' "$jar_sha" sqlite-jdbc-3.53.4.0.jar | sha256sum -c -
    unzip -q kof-0.3.22-beta-windows-x86_64.zip -d "$cache"
    mv sqlite-jdbc-3.53.4.0.jar "$cache/"
)
instalado=$?

if [ "$instalado" -eq 0 ]; then
    export KOF="$cache/kof-0.3.22-beta-windows-x86_64/bin/kof"
    export JAVA="$cache/kof-0.3.22-beta-windows-x86_64/jdk/bin/java"
    export SQLITE_JDBC="$cache/sqlite-jdbc-3.53.4.0.jar"
    bash scripts/build.sh && bash scripts/test.sh && bash scripts/demo.sh
else
    echo 'instalação falhou: nada foi configurado nem executado' >&2
    (exit "$instalado")
fi
```

Instale o ripgrep antes dos testes, por exemplo com
`winget install BurntSushi.ripgrep.MSVC`, e abra um terminal novo para que ele entre no
PATH. Use `bin/kof` no Git Bash; `bin/kof.bat` é o launcher para cmd e PowerShell. Os
scripts definem `stdout.encoding` e `stderr.encoding` como UTF-8 porque o padrão do JVM
no Windows é Cp1252, que corrompe acentos na saída.

`make build`, ou `bash scripts/build.sh`, gera as classes em `build/classes`.
`make test` verifica contratos de estado, erros SQL, reabertura, disputa entre
processos e recuperação após `SIGKILL`. `make demo` inicia um produtor e um
consumidor em processos separados, usando um banco temporário removido ao final.

Para usar instalações próprias, configure `KOF`, `JAVA` e `SQLITE_JDBC` com
caminhos absolutos. No Git Bash, use a forma POSIX (`/c/Users/...`): os scripts montam
o classpath separado por `:`, e um caminho com letra de unidade (`C:/Users/...`) é
interpretado como dois caminhos, resultando em `ClassNotFoundException`. O driver deve estar no classpath da aplicação. Os scripts
já configuram esse classpath; `kofdeps` declara a dependência para outros builds.

## Exemplo persistente

Na raiz do repositório:

```sh
KOF_ACTION=enqueue KOF_PAYLOAD='Gerar relatório mensal' bash scripts/example.sh
KOF_ACTION=work bash scripts/example.sh
KOF_ACTION=show KOF_ID='<id impresso pelo produtor>' bash scripts/example.sh
```

O exemplo usa `jobs.db` no diretório atual. Defina `KOF_DATABASE` para escolher
outro caminho. O consumidor processa `print.v1` até não haver trabalho disponível
e então termina. Para consumir continuamente, a aplicação pode chamar `runOnce`
em um loop e aguardar brevemente quando ele retornar `false`.

Um handler implementa uma interface Kof:

```kof
import koflow.JobStore
import koflow.JobHandler
import koflow.Worker

class ReportHandler implements JobHandler {
    public void execute(String id, String payload, Int attempt) {
        println("Relatório " + id + ": " + payload)
    }
}

main() {
    var jobs = JobStore("reports.db")
    var id = jobs.enqueue("report.v1", "setembro", 3)
    var worker = Worker(jobs, "report.v1", 60000L)
    worker.runOnce(ReportHandler())
    println(jobs.get(id).status)
}
```

Adicione o diretório `koflow/` à raiz do módulo da aplicação. Compile a partir
dessa raiz para resolver os imports. [O exemplo completo](examples/basic/Main.kf)
separa produção, consumo e consulta.

## Contrato de execução

- `enqueue(kind, payload, maxAttempts)` retorna um UUID depois de persistir o job.
  O payload é texto opaco; a aplicação pode usar JSON. O nome `kind` identifica
  o handler e pode incluir uma versão, como `report.v1`.
- `enqueueAt(kind, payload, maxAttempts, availableAt)` enfileira para execução não
  antes de `availableAt`, em milissegundos desde a época. Não existe recorrência:
  o job roda uma vez, como qualquer outro.
- `Worker(store, kind, leaseMillis)` executa um handler por chamada a `runOnce`.
  `false` significa que nenhum job estava disponível; `true` significa que uma
  tentativa foi tratada, inclusive quando o handler falhou. Consulte `get(id)`
  para saber o resultado.
- Estados: `pending`, `running`, `succeeded` e `failed`. O contador começa em zero
  e aumenta em cada concessão confirmada. Erros de handler voltam a `pending`
  até o limite de 1 a 1000 tentativas; depois viram `failed`.
- Um job só é elegível quando `available_at` já passou. Uma falha com orçamento
  restante agenda a próxima tentativa para `agora + atraso`, com o atraso dobrando a
  cada tentativa a partir de 1 s, limitado a 1 h, mais uma dispersão de até 20% para
  que jobs diferentes não retornem todos no mesmo instante.
- Uma concessão expirada **não** recebe atraso: o prazo vencido já foi a espera.
- A seleção respeita a ordem de inserção entre os jobs elegíveis do mesmo `kind`.
  Um job agendado para o futuro não é escolhido antes do instante, mesmo sendo o mais
  antigo. Jobs de nomes sem consumidor permanecem pendentes.
- Uma tentativa tem uma concessão de execução (*lease*) entre 1 ms e 24 h.
  Na expiração, a próxima chamada de claim para aquele `kind` recupera o job ou
  o encerra se o limite de tentativas foi atingido. Uma queda depois do claim
  consome a tentativa mesmo que o handler ainda não tenha começado.
- Confirmações exigem a tentativa vigente e prazo ainda válido. Uma confirmação
  antiga ou expirada é recusada. Perda da concessão e falhas de armazenamento
  propagam erro; o consumidor deve decidir como reiniciar ou alertar.

O processamento pode repetir. Se o efeito externo ocorrer e o processo morrer
antes da confirmação, outra tentativa poderá executar o mesmo efeito. Use o `id`
do job como chave de idempotência no serviço de destino. Não há garantia de
*exactly-once*, nem de sucesso final após esgotar as tentativas.

Uma lease não interrompe o handler. Configure um prazo com margem para a operação
e para a contenção do banco. Handlers que excedem esse prazo podem se sobrepor a
uma nova tentativa. O relógio deve ser consistente entre os processos do mesmo host.

## API de armazenamento

`JobStore` oferece também primitivas para controle explícito:

| Operação | Resultado |
| --- | --- |
| `get(id)` | Snapshot `Job`; lança erro se não existir. |
| `claim(kind, now, leaseMillis)` | Lista com zero ou um `Job`, com número da tentativa e prazo persistidos. |
| `succeed(job, now)` | `true` se confirmou sucesso; `false` se a concessão não é mais válida. |
| `fail(job, error, now)` | `true` se registrou falha/retry; `false` se a concessão não é mais válida. |
| `attempts(id)` | Histórico do job, em ordem de tentativa; lança erro se o job não existir. |

Cada tentativa vira uma linha de histórico no mesmo instante em que o estado do job
muda, com `started_at`, `finished_at`, `error` e um `result`:

| `result` | Significado |
| --- | --- |
| `running` | Concedida e ainda sem confirmação válida. |
| `succeeded` | O handler confirmou sucesso dentro do prazo. |
| `failed` | O handler falhou e a falha foi confirmada dentro do prazo. |
| `expired` | A concessão venceu sem confirmação. |

`expired` não é `failed`: o runtime sabe que a tentativa foi concedida e não confirmada,
mas não sabe se o efeito externo chegou a acontecer. O esgotamento do orçamento aparece
no job (`status` igual a `failed`), não como resultado de tentativa.

```kof
for (var attempt in jobs.attempts(id)) {
    println(attempt.attempt + " " + attempt.result + " " + attempt.error)
}
```

`now` usa milissegundos desde Unix epoch (`Long`); o Worker fornece `time.now()`.
Os snapshots não são atualizados em memória: consulte novamente para ler mudanças.
O campo `last_error` guarda até 4096 unidades UTF-16 e é limpo em caso de sucesso.
Erros podem conter dados da aplicação; restrinja o acesso ao arquivo do banco.

## Limites operacionais

Use um arquivo SQLite dedicado em disco local, com journal `DELETE`. O runtime
usa `synchronous=FULL`, espera até 5 segundos por locks e recusa identidade ou
versão de schema incompatível. O diretório pai deve existir. Não use `:memory:`,
URI `file:`, compartilhamento de rede ou o mesmo arquivo de outro sistema.

Esta versão não inclui cron, recorrência, prioridade, heartbeat, cancelamento,
timeout preemptivo, pool gerenciado, servidor, dashboard, DAGs ou workflows duráveis.
O agendamento é pontual: um job roda uma vez. O atraso entre tentativas é fixo em
contrato, não configurável. Jobs e histórico não são removidos automaticamente — não há
política de retenção. A disputa de claims entre processos é testada; outros backends Kof
e falhas físicas de disco ou energia não foram validados.

Bancos criados por versões anteriores são migrados na abertura, dentro de uma transação:
a coluna de elegibilidade entra com valor neutro e nenhum job é reescrito. As tentativas
concluídas antes da migração não aparecem no histórico, porque nunca foram registradas.
A exceção é o job que estava em execução no momento da migração: ele recebe a linha da
tentativa vigente, necessária para que a confirmação ou a expiração dela funcionem, com
`started_at` igual a `0` indicando **início desconhecido** — não um início na época.

## Encontrou um problema?

[Abra uma issue](https://github.com/Jovinull/Koflow/issues/new) com a versão da Kof,
o sistema operacional, um exemplo mínimo e o comportamento esperado e observado.
Para conferir o pacote localmente, execute `make test` e `make demo`.

O Koflow é um projeto independente para o ecossistema Kof. Conheça também a
[linguagem e seu compilador](https://github.com/KofLang/Kof4j) e a
[documentação oficial](https://koflang.github.io/).

## Licença

Distribuído sob a [Apache License 2.0](LICENSE). A licença concede uso, modificação e
distribuição, inclusive comercial, com concessão expressa de patentes e exigência de
preservar avisos de copyright e licença nas cópias.

