using System;
using System.Runtime.InteropServices;
using System.Threading;

namespace Negaflow.Interop;

/// <summary>
/// 한 번의 <see cref="NativeDevelopExporter.Run"/> 또는
/// <see cref="NativeDevelopExporter.Preview"/> 호출을 취소하고 진행 상황을 읽는 손잡이입니다.
/// </summary>
/// <remarks>
/// <para>
/// 현상 호출은 블로킹이므로 작업자 스레드에서 돕니다. UI 스레드는 이 객체로 취소를 요청하고,
/// 자기 타이머로 <see cref="ProgressPermille"/> 과 <see cref="Stage"/> 를 읽습니다. 네이티브가
/// 관리 코드를 콜백하지 않으므로 재진입도, 호출 동안 살려 둘 델리게이트도 없습니다.
/// </para>
/// <para>
/// 상태는 GC 힙이 아니라 고정 주소의 비관리 메모리에 둡니다. 긴 블로킹 호출 동안 관리 객체를
/// 고정해 두지 않기 위해서입니다. <see cref="Dispose"/> 는 호출이 <b>돌아온 뒤에만</b>
/// 부르십시오. 실행 중에 해제하면 네이티브가 해제된 주소를 읽습니다.
/// </para>
/// </remarks>
public sealed unsafe class DevelopRun : IDisposable
{
    private readonly CancellationTokenRegistration registration;
    private nint state;

    /// <summary>
    /// 취소 상태를 만듭니다. <paramref name="cancellationToken"/> 을 주면 그 토큰이 취소될 때
    /// 자동으로 <see cref="Cancel"/> 이 호출됩니다.
    /// </summary>
    public DevelopRun(CancellationToken cancellationToken = default)
    {
        NativeDevelopRunStateV1* allocated = (NativeDevelopRunStateV1*)NativeMemory.AllocZeroed(
            (nuint)sizeof(NativeDevelopRunStateV1));
        allocated->StructSize = (uint)sizeof(NativeDevelopRunStateV1);
        state = (nint)allocated;

        if (cancellationToken.CanBeCanceled)
        {
            // 이미 취소된 토큰이면 여기서 바로 래치가 서고, 첫 poll 에서 실행이 멈춥니다.
            registration = cancellationToken.Register(
                static handle => ((DevelopRun)handle!).Cancel(),
                this);
        }
    }

    /// <summary>
    /// 실행을 멈추라고 요청합니다. 어느 스레드에서든, 몇 번이든 부를 수 있습니다.
    /// </summary>
    /// <remarks>
    /// 협조적 취소입니다. 단계 경계와 TIFF 디코드의 행 덩어리마다 확인하므로 즉시가 아니라
    /// 다음 확인 지점에서 멈춥니다. 게시가 시작된 뒤에는 반쪽짜리 파일을 남기지 않기 위해
    /// 일부러 확인하지 않습니다.
    /// </remarks>
    public void Cancel()
    {
        NativeDevelopRunStateV1* current = Current;
        if (current is not null)
        {
            Volatile.Write(ref current->CancelRequested, 1U);
        }
    }

    /// <summary>취소가 요청됐는지 여부입니다.</summary>
    public bool IsCancelRequested
    {
        get
        {
            NativeDevelopRunStateV1* current = Current;
            return current is not null && Volatile.Read(ref current->CancelRequested) != 0U;
        }
    }

    /// <summary>
    /// 지금 실행 중인 단계입니다. 시작 전에는 <see cref="DevelopExportStage.None"/> 입니다.
    /// </summary>
    public DevelopExportStage Stage
    {
        get
        {
            NativeDevelopRunStateV1* current = Current;
            return current is null
                ? DevelopExportStage.None
                : (DevelopExportStage)Volatile.Read(ref current->Stage);
        }
    }

    /// <summary>
    /// 0...1000 의 진행도입니다. 이 요청이 실제로 실행할 단계들의 비용 추정에 따른 값이며,
    /// 뒤로 가지 않고 성공했을 때만 1000 에 도달합니다.
    /// </summary>
    public int ProgressPermille
    {
        get
        {
            NativeDevelopRunStateV1* current = Current;
            return current is null ? 0 : (int)Volatile.Read(ref current->ProgressPermille);
        }
    }

    /// <summary>진행도를 0...1 실수로 읽습니다.</summary>
    public double Progress => ProgressPermille / 1000.0;

    public void Dispose()
    {
        // 등록을 먼저 정리합니다. Dispose 가 진행 중인 콜백이 끝날 때까지 기다리므로,
        // 그 뒤에 해제하면 취소 콜백이 해제된 메모리를 건드릴 수 없습니다.
        registration.Dispose();
        nint previous = Interlocked.Exchange(ref state, 0);
        if (previous != 0)
        {
            NativeMemory.Free((void*)previous);
        }
    }

    /// <summary>
    /// 네이티브 호출에 넘길 포인터입니다. 해제된 뒤에는 null 이므로 호출은 취소 없이 돕니다.
    /// </summary>
    internal NativeDevelopRunStateV1* StatePointer => Current;

    private NativeDevelopRunStateV1* Current =>
        (NativeDevelopRunStateV1*)Volatile.Read(ref state);
}
