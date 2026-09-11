# Koflow

### O processo pode parar. O trabalho continua registrado.

[![CI](https://github.com/Jovinull/Koflow/actions/workflows/ci.yml/badge.svg)](https://github.com/Jovinull/Koflow/actions/workflows/ci.yml)
[![Kof](https://img.shields.io/badge/Kof-0.3.22--beta-7c3aed)](https://github.com/KofLang/Kof4j)
![Backend](https://img.shields.io/badge/backend-JVM-2563eb)
![SQLite](https://img.shields.io/badge/storage-SQLite-003b57)
![Status](https://img.shields.io/badge/status-experimental-d97706)

**Background jobs persistentes, escritos em [Kof](https://github.com/KofLang/Kof4j).**

Envie o trabalho para depois, execute em outro processo e mantenha seu estado salvo.
O Koflow usa SQLite para registrar jobs, controlar tentativas e recuperar execuções
interrompidas — com uma biblioteca pequena, handlers explícitos e testes de falha reais.

É uma base para tarefas como gerar relatórios, processar arquivos e integrar serviços
fora da requisição principal. A biblioteca, os exemplos e as asserções são escritos
em Kof; a execução atual usa o JVM.

## O que já funciona

- **Persistência:** jobs e payloads sobrevivem ao encerramento do processo.
- **Retries limitados:** falhas podem ser repetidas até o orçamento de tentativas.
- **Recuperação:** uma execução interrompida volta a ficar disponível após expirar seu prazo.
- **Controle de posse:** confirmações de tentativas antigas são rejeitadas.
- **Inspeção simples:** consulte estado, tentativas e último erro pelo ID do job.

O projeto é **experimental**. A recuperação foi testada com `SIGKILL`, e a disputa
por um job foi exercitada entre oito processos. Efeitos externos podem se repetir;
handlers devem ser idempotentes. Veja o [contrato de execução](#contrato-de-execução).

## Comece por aqui

Ambiente validado: Linux x86_64, Kof 0.3.22-beta/JVM, JDK 21 e SQLite JDBC 3.53.4.0.
Os scripts precisam de Bash, Make, curl, tar e coreutils; os testes também usam `rg`
(ripgrep). O bootstrap baixa versões fixas, confere SHA-256 e instala em
`${XDG_CACHE_HOME:-$HOME/.cache}/koflow`. A distribuição Kof inclui o JDK.

```sh
git clone https://github.com/Jovinull/Koflow.git
cd Koflow
make bootstrap
make build
make test
make demo
```

`make build` gera as classes em `build/classes`. `make test` verifica contratos
de estado, erros SQL, reabertura, disputa entre processos e recuperação após
`SIGKILL`. `make demo` inicia um produtor e um consumidor em processos separados,
usando um banco temporário que é removido ao final.

Para usar instalações próprias, configure `KOF`, `JAVA` e `SQLITE_JDBC` com
caminhos absolutos. O driver deve estar no classpath da aplicação. Os scripts
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
- `Worker(store, kind, leaseMillis)` executa um handler por chamada a `runOnce`.
  `false` significa que nenhum job estava disponível; `true` significa que uma
  tentativa foi tratada, inclusive quando o handler falhou. Consulte `get(id)`
  para saber o resultado.
- Estados: `pending`, `running`, `succeeded` e `failed`. O contador começa em zero
  e aumenta em cada concessão confirmada. Erros de handler voltam a `pending`
  imediatamente, até o limite de 1 a 1000 tentativas; depois viram `failed`.
- A seleção respeita a ordem de inserção dos jobs disponíveis do mesmo `kind`.
  Um job que falha pode ser selecionado novamente antes dos seguintes. Jobs de
  nomes sem consumidor permanecem pendentes.
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

`now` usa milissegundos desde Unix epoch (`Long`); o Worker fornece `time.now()`.
Os snapshots não são atualizados em memória: consulte novamente para ler mudanças.
O campo `last_error` guarda até 4096 unidades UTF-16 e é limpo em caso de sucesso.
Erros podem conter dados da aplicação; restrinja o acesso ao arquivo do banco.

## Limites operacionais

Use um arquivo SQLite dedicado em disco local, com journal `DELETE`. A biblioteca
usa `synchronous=FULL`, espera até 5 segundos por locks e recusa identidade ou
versão de schema incompatível. O diretório pai deve existir. Não use `:memory:`,
URI `file:`, compartilhamento de rede ou o mesmo arquivo de outro sistema.

Este pacote não inclui cron, agendamento futuro, backoff, heartbeat, cancelamento,
timeout preemptivo, pool gerenciado, servidor, dashboard, DAGs ou workflows duráveis.
Não remove jobs automaticamente e mantém apenas o último erro, sem histórico
completo de tentativas. A disputa de claims entre processos é testada; outros
backends Kof e falhas físicas de disco ou energia não foram validados.

## Encontrou um problema?

[Abra uma issue](https://github.com/Jovinull/Koflow/issues/new) com a versão da Kof,
o sistema operacional, um exemplo mínimo e o comportamento esperado e observado.
Para conferir o pacote localmente, execute `make test` e `make demo`.

O Koflow é um projeto independente para o ecossistema Kof. Conheça também a
[linguagem e seu compilador](https://github.com/KofLang/Kof4j) e a
[documentação oficial](https://koflang.github.io/).
