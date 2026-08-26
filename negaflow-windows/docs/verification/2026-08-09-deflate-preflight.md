# 2026-08-09 Deflate 사전 검사 검증

대상: x64 Debug, TIFF compression tag `8`의 독립 zlib/Deflate 검사와 WIC 연결

## 실행

```powershell
cmake --preset x64-debug
cmake --build --preset x64-debug --target negaflow_tiff_probe_tests negaflow_wic_tiff_decoder_tests negaflow_cli
ctest --test-dir out\build\native\x64-debug -C Debug -R "^native\.(tiff_probe|wic_tiff_decode)$" --output-on-failure
```

## 결과

- build 성공, native targeted test 2/2 통과
- stored, fixed-Huffman, dynamic-Huffman zlib stream이 독립 검사를 통과한 뒤 WIC에서 decode됨
- stored/fixed 1×1 RGB16 pixel exact 일치
- dynamic 32×32 RGB16의 6,144 복원 byte와 첫·마지막 pixel exact 일치
- stored block LEN/NLEN 모순과 Adler-32 불일치는 `invalid_compressed_data`로 WIC 전에 거부
- 17-byte stream에 16-byte compressed-input 한도를 적용하면 WIC 전에 거부

이번 검증은 x64 Debug 합성 입력 범위입니다. x64 Release, ARM64 runtime, 실제 사용자 Deflate TIFF,
WIC 내부 압축 해제 hard deadline과 fuzz/ASan은 검증하지 않았습니다.
