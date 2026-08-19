[CmdletBinding()]
param(
    # 이벤트 로그의 "오류 오프셋"(모듈 기준 RVA), 예: 0x1546cb
    [Parameter(Mandatory)][string]$Rva,
    [string]$Module = "out\build\native\x64-release\Release\Negaflow.Native.dll"
)

# 크래시 주소를 함수·파일·줄로 되돌립니다.
#
# WER 은 "오류 있는 모듈 + 오프셋" 만 남깁니다. 그 오프셋은 모듈 기준 RVA 이므로,
# 같은 빌드의 PDB 만 있으면 dbghelp 로 이름을 찾을 수 있습니다. Release 빌드도
# PDB 를 내도록 cmake/CompilerWarnings.cmake 에서 /Zi·/DEBUG 를 켜 두었습니다.
#
#   .\scripts\symbolize-rva.ps1 -Rva 0x1546cb

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$modulePath = if ([System.IO.Path]::IsPathRooted($Module)) { $Module } else { Join-Path $projectRoot $Module }
if (-not (Test-Path -LiteralPath $modulePath)) {
    throw "Module not found: $modulePath"
}
$symbolDirectory = Split-Path -Parent $modulePath
$offset = [Convert]::ToUInt64($Rva.Replace('0x', ''), 16)

$signature = @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class Symbolizer
{
    [DllImport("dbghelp.dll", SetLastError = true, CharSet = CharSet.Ansi)]
    public static extern bool SymInitialize(IntPtr process, string searchPath, bool invadeProcess);

    [DllImport("dbghelp.dll", SetLastError = true)]
    public static extern uint SymSetOptions(uint options);

    [DllImport("dbghelp.dll", SetLastError = true, CharSet = CharSet.Ansi)]
    public static extern ulong SymLoadModuleEx(
        IntPtr process, IntPtr file, string imageName, string moduleName,
        ulong baseOfDll, uint sizeOfDll, IntPtr data, uint flags);

    [DllImport("dbghelp.dll", SetLastError = true, CharSet = CharSet.Ansi)]
    public static extern bool SymFromAddr(IntPtr process, ulong address, out ulong displacement, IntPtr symbol);

    [DllImport("dbghelp.dll", SetLastError = true, CharSet = CharSet.Ansi)]
    public static extern bool SymGetLineFromAddr64(IntPtr process, ulong address, out uint displacement, ref IMAGEHLP_LINE64 line);

    [DllImport("dbghelp.dll", SetLastError = true)]
    public static extern bool SymCleanup(IntPtr process);

    [StructLayout(LayoutKind.Sequential)]
    public struct IMAGEHLP_LINE64
    {
        public uint SizeOfStruct;
        public IntPtr Key;
        public uint LineNumber;
        public IntPtr FileName;
        public ulong Address;
    }

    public static string Resolve(string modulePath, string searchPath, ulong rva)
    {
        IntPtr process = new IntPtr(-1);
        // DEFERRED_LOADS 를 켜면 PDB 를 미루다 못 찾습니다(126). 바로 읽습니다.
        SymSetOptions(0x00000002 /* UNDNAME */ | 0x00000800 /* LOAD_LINES */);
        if (!SymInitialize(process, searchPath, false))
        {
            return "SymInitialize failed: " + Marshal.GetLastWin32Error();
        }
        try
        {
            uint imageSize = 0;
            try { imageSize = (uint)new System.IO.FileInfo(modulePath).Length; } catch { }
            ulong moduleBase = SymLoadModuleEx(process, IntPtr.Zero, modulePath, null, 0x10000000UL, imageSize, IntPtr.Zero, 0);
            if (moduleBase == 0)
            {
                return "SymLoadModuleEx failed: " + Marshal.GetLastWin32Error();
            }
            ulong address = moduleBase + rva;

            // SYMBOL_INFO: 고정 부분 88바이트 + 이름 버퍼.
            int nameCapacity = 1024;
            int size = 88 + nameCapacity;
            IntPtr buffer = Marshal.AllocHGlobal(size);
            try
            {
                for (int index = 0; index < size; index++) { Marshal.WriteByte(buffer, index, 0); }
                Marshal.WriteInt32(buffer, 0, 88);              // SizeOfStruct
                Marshal.WriteInt32(buffer, 76, nameCapacity);   // MaxNameLen
                ulong displacement;
                string result;
                if (SymFromAddr(process, address, out displacement, buffer))
                {
                    string name = Marshal.PtrToStringAnsi(IntPtr.Add(buffer, 84));
                    result = name + " + 0x" + displacement.ToString("x");
                }
                else
                {
                    result = "SymFromAddr failed: " + Marshal.GetLastWin32Error();
                }

                IMAGEHLP_LINE64 line = new IMAGEHLP_LINE64();
                line.SizeOfStruct = (uint)Marshal.SizeOf(typeof(IMAGEHLP_LINE64));
                uint lineDisplacement;
                if (SymGetLineFromAddr64(process, address, out lineDisplacement, ref line))
                {
                    string file = Marshal.PtrToStringAnsi(line.FileName);
                    result += "\n    " + file + ":" + line.LineNumber;
                }
                return result;
            }
            finally
            {
                Marshal.FreeHGlobal(buffer);
            }
        }
        finally
        {
            SymCleanup(process);
        }
    }
}
'@
if (-not ("Symbolizer" -as [type])) { Add-Type -TypeDefinition $signature }

Write-Output ("module: {0}" -f $modulePath)
Write-Output ("rva:    0x{0:x}" -f $offset)
Write-Output ([Symbolizer]::Resolve($modulePath, $symbolDirectory, $offset))
