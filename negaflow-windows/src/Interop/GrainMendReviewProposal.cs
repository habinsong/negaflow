using System.Runtime.InteropServices;

namespace Negaflow.Interop;

/// <summary>
/// 한 번 검출한 GrainMend 후보의 정확한 네이티브 컴포넌트 소유권입니다. 수락하거나
/// 취소할 때 폐기하며, 영구 레시피에는 최종 RGBA8 마스크만 들어갑니다.
/// </summary>
public sealed unsafe class GrainMendReviewProposal : IGrainMendReviewProposal
{
    private const uint StatusOk = 0U;
    private const uint AcceptedOk = 0U;
    private const uint AcceptedEmpty = 1U;
    private const uint AcceptedInvalidGeometry = 2U;
    private const uint AcceptedAllocationFailed = 3U;

    private readonly object gate = new();
    private GrainMendReviewSafeHandle? handle;

    internal GrainMendReviewProposal(
        nint nativeHandle,
        uint width,
        uint height,
        uint sourceWidth,
        uint sourceHeight,
        uint roiX,
        uint roiY,
        uint roiWidth,
        uint roiHeight,
        IReadOnlyList<GrainMendComponent> components)
    {
        if (nativeHandle == 0)
        {
            throw new ArgumentException("The GrainMend review handle is null.", nameof(nativeHandle));
        }
        handle = new GrainMendReviewSafeHandle(nativeHandle);
        Width = width;
        Height = height;
        SourceWidth = sourceWidth;
        SourceHeight = sourceHeight;
        RoiX = roiX;
        RoiY = roiY;
        RoiWidth = roiWidth;
        RoiHeight = roiHeight;
        Components = components;
    }

    public uint Width { get; }
    public uint Height { get; }
    public uint SourceWidth { get; }
    public uint SourceHeight { get; }
    public uint RoiX { get; }
    public uint RoiY { get; }
    public uint RoiWidth { get; }
    public uint RoiHeight { get; }
    public IReadOnlyList<GrainMendComponent> Components { get; }

    public bool TryHit(int x, int y, uint radius, out int componentIndex)
    {
        lock (gate)
        {
            GrainMendReviewSafeHandle current = RequireHandle();
            NativeGrainMendReviewHitV1 hit = new()
            {
                StructSize = (uint)sizeof(NativeGrainMendReviewHitV1),
            };
            uint status = NativeGrainMendDetect.nf_grain_mend_review_hit_test_v1(
                current.DangerousGetHandle(), x, y, radius, &hit);
            ThrowNativeFailure("nf_grain_mend_review_hit_test_v1", status);
            if (hit.Found == 0U)
            {
                componentIndex = -1;
                return false;
            }
            if (hit.Found != 1U || hit.ComponentIndex >= (ulong)Components.Count)
            {
                throw ContractViolation("The native GrainMend hit test returned an invalid component.");
            }
            componentIndex = checked((int)hit.ComponentIndex);
            return true;
        }
    }

    public GrainMendAcceptedRegion? BuildAccepted(ReadOnlySpan<byte> excludedComponents)
    {
        if (excludedComponents.Length != Components.Count)
        {
            throw new ArgumentException(
                "The GrainMend exclusion array must match the component count.",
                nameof(excludedComponents));
        }

        GrainMendReviewSafeHandle current;
        bool addedReference = false;
        lock (gate)
        {
            current = RequireHandle();
            current.DangerousAddRef(ref addedReference);
        }
        try
        {
            NativeGrainMendAcceptedRegionV1 accepted = new()
            {
                StructSize = (uint)sizeof(NativeGrainMendAcceptedRegionV1),
            };
            nint acceptedHandle = 0;
            fixed (byte* excluded = excludedComponents)
            {
                uint status = NativeGrainMendDetect.nf_grain_mend_review_build_accepted_v1(
                    current.DangerousGetHandle(),
                    excludedComponents.IsEmpty ? null : excluded,
                    (ulong)excludedComponents.Length,
                    &accepted,
                    &acceptedHandle);
                ThrowNativeFailure("nf_grain_mend_review_build_accepted_v1", status);
            }

            if (accepted.StructSize != (uint)sizeof(NativeGrainMendAcceptedRegionV1))
            {
                ReleaseAccepted(acceptedHandle);
                throw ContractViolation("The native GrainMend accepted descriptor has an invalid size.");
            }
            if (accepted.Status == AcceptedEmpty)
            {
                if (acceptedHandle != 0 || accepted.MaskByteCount != 0UL ||
                    accepted.IncludedComponentCount != 0UL)
                {
                    ReleaseAccepted(acceptedHandle);
                    throw ContractViolation("An empty GrainMend acceptance returned payload ownership.");
                }
                return null;
            }
            if (accepted.Status == AcceptedInvalidGeometry)
            {
                ReleaseAccepted(acceptedHandle);
                throw ContractViolation("The native GrainMend review reported invalid accepted geometry.");
            }
            if (accepted.Status == AcceptedAllocationFailed)
            {
                ReleaseAccepted(acceptedHandle);
                throw new NativeBootstrapException(
                    NativeBootstrapFailure.NativeCallFailed,
                    "The native GrainMend review could not allocate the accepted region.");
            }
            if (accepted.Status != AcceptedOk || acceptedHandle == 0)
            {
                ReleaseAccepted(acceptedHandle);
                throw ContractViolation("The native GrainMend review returned an unknown accepted state.");
            }

            try
            {
                ValidateAcceptedDescriptor(
                    accepted,
                    RoiX,
                    RoiY,
                    RoiWidth,
                    RoiHeight,
                    Components.Count);
                byte[] rgba = new byte[(int)accepted.MaskByteCount];
                fixed (byte* output = rgba)
                {
                    uint status = NativeGrainMendDetect.nf_grain_mend_accepted_region_copy_mask_v1(
                        acceptedHandle, output, (ulong)rgba.Length);
                    ThrowNativeFailure("nf_grain_mend_accepted_region_copy_mask_v1", status);
                }
                return new GrainMendAcceptedRegion(
                    accepted.RoiX,
                    accepted.RoiY,
                    accepted.Width,
                    accepted.Height,
                    rgba,
                    accepted.IncludedComponentCount);
            }
            finally
            {
                NativeGrainMendDetect.nf_grain_mend_accepted_region_destroy_v1(acceptedHandle);
            }
        }
        finally
        {
            if (addedReference)
            {
                current.DangerousRelease();
            }
        }
    }

    internal static void ValidateAcceptedDescriptor(
        NativeGrainMendAcceptedRegionV1 accepted,
        uint proposalRoiX,
        uint proposalRoiY,
        uint proposalRoiWidth,
        uint proposalRoiHeight,
        int componentCount)
    {
        if (accepted.StructSize != (uint)sizeof(NativeGrainMendAcceptedRegionV1) ||
            accepted.Status != AcceptedOk ||
            accepted.Width == 0U || accepted.Height == 0U ||
            accepted.IncludedComponentCount == 0UL ||
            accepted.IncludedComponentCount > (ulong)componentCount)
        {
            throw ContractViolation("The native GrainMend accepted descriptor is inconsistent.");
        }

        ulong pixelCount = (ulong)accepted.Width * accepted.Height;
        if (pixelCount > (ulong)int.MaxValue / 4UL ||
            accepted.MaskByteCount != pixelCount * 4UL)
        {
            throw ContractViolation("The native GrainMend accepted descriptor is inconsistent.");
        }

        if (accepted.RoiX < proposalRoiX || accepted.RoiY < proposalRoiY)
        {
            throw ContractViolation("The native GrainMend accepted region is outside its proposal.");
        }
        uint relativeX = accepted.RoiX - proposalRoiX;
        uint relativeY = accepted.RoiY - proposalRoiY;
        if (relativeX > proposalRoiWidth || relativeY > proposalRoiHeight ||
            accepted.Width > proposalRoiWidth - relativeX ||
            accepted.Height > proposalRoiHeight - relativeY)
        {
            throw ContractViolation("The native GrainMend accepted region is outside its proposal.");
        }
    }

    public void Dispose()
    {
        lock (gate)
        {
            handle?.Dispose();
            handle = null;
        }
        GC.SuppressFinalize(this);
    }

    private GrainMendReviewSafeHandle RequireHandle() =>
        handle is { IsClosed: false, IsInvalid: false } current
            ? current
            : throw new ObjectDisposedException(nameof(GrainMendReviewProposal));

    private static void ReleaseAccepted(nint acceptedHandle)
    {
        if (acceptedHandle != 0)
        {
            NativeGrainMendDetect.nf_grain_mend_accepted_region_destroy_v1(acceptedHandle);
        }
    }

    private static void ThrowNativeFailure(string operation, uint status)
    {
        if (status != StatusOk)
        {
            throw new NativeBootstrapException(
                NativeBootstrapFailure.NativeCallFailed,
                $"{operation} failed with status {status}.");
        }
    }

    private static NativeBootstrapException ContractViolation(string message) =>
        new(NativeBootstrapFailure.ContractViolation, message);
}

internal sealed class GrainMendReviewSafeHandle : SafeHandle
{
    internal GrainMendReviewSafeHandle(nint handleValue)
        : base(nint.Zero, ownsHandle: true)
    {
        SetHandle(handleValue);
    }

    public override bool IsInvalid => handle == nint.Zero;

    protected override bool ReleaseHandle()
    {
        NativeGrainMendDetect.nf_grain_mend_review_destroy_v1(handle);
        return true;
    }
}
