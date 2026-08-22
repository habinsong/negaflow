using System.Security.Cryptography;
using System.Text;

namespace Negaflow.Shell.Diagnostics;

/// <summary>
/// macOS <c>SupportBundlePrivacyHasher</c> 이식본입니다 — 번들마다 새 소금을 만들고
/// SHA-256 앞 12바이트만 16진수로 냅니다.
/// </summary>
/// <remarks>
/// 소금이 번들마다 다르므로 <b>두 번들 사이에서 같은 경로가 같은 해시로 보이지 않습니다.</b>
/// 그것이 목적입니다 — 같은 기계를 여러 번들로 이어 붙일 수 없게 합니다. 대신 한 번들 안에서는
/// 같은 경로가 같은 해시라 "썸네일 캐시와 스캔 원본이 같은 폴더인가" 같은 물음에 답할 수 있습니다.
/// </remarks>
public sealed class SupportBundlePrivacyHasher
{
    private readonly byte[] salt;

    public SupportBundlePrivacyHasher()
        : this(Encoding.UTF8.GetBytes(Guid.NewGuid().ToString()))
    {
    }

    public SupportBundlePrivacyHasher(byte[] salt)
    {
        ArgumentNullException.ThrowIfNull(salt);
        this.salt = salt;
    }

    public string Hash(string value)
    {
        ArgumentNullException.ThrowIfNull(value);
        byte[] payload = new byte[salt.Length + Encoding.UTF8.GetByteCount(value)];
        salt.CopyTo(payload, 0);
        Encoding.UTF8.GetBytes(value, payload.AsSpan(salt.Length));
        Span<byte> digest = stackalloc byte[32];
        SHA256.HashData(payload, digest);
        return Convert.ToHexStringLower(digest[..12]);
    }
}

/// <summary>macOS <c>ScannerPluginApprovalState.supportBundleCode</c> 자리입니다.</summary>
public static class ScannerPluginApprovalCodes
{
    public static string Code(ScannerPluginApprovalState state) => state switch
    {
        ScannerPluginApprovalState.Approved => "approved",
        ScannerPluginApprovalState.Changed => "identityChanged",
        _ => "approvalRequired",
    };
}
