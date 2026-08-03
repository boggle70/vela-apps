# vela-apps
q-vela application components

# ProjectName

한 문장 목적. (예: 이기종 가속기 기반 분산 추론 서비스 스택)

## 저장소 구성

| Repository | 역할 | 계층 | 언어 | 상태 |
|---|---|---|---|---|
| [`proj-core`](…) | 스케줄러·API 서버 | Control | Python | ![](https://img.shields.io/badge/stable-green) |
| [`proj-runtime`](…) | 가속기 런타임 추상화 | Runtime | C++ | ![](https://img.shields.io/badge/beta-yellow) |
| [`proj-transport`](…) | RDMA 전송 계층 | Data | C | ![](https://img.shields.io/badge/beta-yellow) |
| [`proj-bench`](…) | 벤치마크·재현 스크립트 | Tooling | Python | ![](https://img.shields.io/badge/wip-lightgrey) |
| [`proj-docs`](…) | 설계 문서·논문 자료 | Docs | — | — |

## 의존 관계

```mermaid
graph TD
    core[proj-core] --> runtime[proj-runtime]
    runtime --> transport[proj-transport]
    bench[proj-bench] -.측정.-> core
    docs[proj-docs] -.참조.-> core
    
    classDef control fill:#e3f2fd,stroke:#1565c0
    classDef data fill:#fff3e0,stroke:#ef6c00
    class core control
    class transport,runtime data
```

실선 = 빌드/런타임 의존, 점선 = 느슨한 참조

## 버전 결속

이 repo는 각 구성요소를 submodule로 고정합니다.

| Submodule | 경로 | 고정 태그 |
|---|---|---|
| proj-core | `components/core` | `v0.4.1` |
| proj-runtime | `components/runtime` | `v0.3.0` |

## 시작하기

```bash
git clone --recurse-submodules https://github.com/org/project-meta.git
cd project-meta && make bootstrap
```

## 기여 시 어느 repo로 갈까?

| 하고 싶은 일 | 대상 repo |
|---|---|
| 새 가속기 백엔드 추가 | `proj-runtime` |
| 스케줄링 정책 변경 | `proj-core` |
| 전송 성능 튜닝 | `proj-transport` |
