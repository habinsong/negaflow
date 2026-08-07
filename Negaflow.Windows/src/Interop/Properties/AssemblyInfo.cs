using System.Runtime.CompilerServices;

[assembly: InternalsVisibleTo("Negaflow.Interop.ContractTests")]

// 셸 테스트는 네이티브 엔진 없이 현상 결과를 만들어야 합니다. DevelopExportResult 의 생성자를
// 공개하는 대신 여기서 열어 두어, 제품 API 에는 엔진만 만들 수 있는 형태로 남깁니다.
[assembly: InternalsVisibleTo("Negaflow.Shell.UnitTests")]
