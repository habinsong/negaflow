# 압축 TIFF 사전 검사 공식 근거와 권리 검토

기준일: 2026-08-04

## TIFF와 Windows API 근거

- [TIFF Revision 6.0](https://www.itu.int/itudoc/itu-t/com16/tiff-fx/docs/tiff6.pdf) Section 13은 LZW
  strip별 독립 사전, 첫 ClearCode, 마지막 EOI, high-to-low bit 순서, 최대 12-bit와 decoder의
  510/1022/2046 early-change를 정의합니다. entry 4094 사용 시 Clear를 기록해 13-bit 해석을 피하도록
  설명합니다.
- [WIC 개요](https://learn.microsoft.com/en-us/windows/win32/wic/-wic-about-windows-imaging-codec)와
  [WIC TIFF 형식 개요](https://learn.microsoft.com/en-us/windows/win32/wic/tiff-format-overview)는 Windows
  native TIFF codec과 지원 compression/pixel 형식을 설명하지만 손상 compressed stream을 strict하게
  거부한다는 보장은 제공하지 않습니다.
- [`IWICBitmapSource::CopyPixels`](https://learn.microsoft.com/en-us/windows/win32/api/wincodec/nf-wincodec-iwicbitmapsource-copypixels)는
  동기식 ROI·stride·caller buffer 계약입니다. 호출 내부의 hard deadline이나 취소 callback 계약은
  없으므로 현재 cooperative cancellation 한계를 문서에 남깁니다.
- [RFC 1950](https://www.rfc-editor.org/rfc/rfc1950)은 zlib CMF/FLG, window 크기, preset dictionary,
  Adler-32와 checksum 검증 의무를 정의합니다.
- [RFC 1951](https://www.rfc-editor.org/rfc/rfc1951)는 Deflate stored/fixed/dynamic block, canonical
  Huffman code와 32 KiB LZ77 window를 정의합니다. 구현은 두 형식의 규칙만 독립적으로 적용했으며 RFC
  sample code나 외부 decoder source를 사용하지 않았습니다.

## 로컬 WIC 관찰의 해석

정상 zlib stored block과, LEN/NLEN은 65,535 byte를 선언하지만 bounded TIFF segment에는 작은 RGB16
payload만 남긴 손상 변형을 test 코드로 합성했습니다. 현재 로컬 Microsoft WIC는 두 입력 모두에서 작은
원래 sample을 반환했습니다. 이 결과로 WIC 전체가 항상 검증을 생략한다고 단정하지 않습니다. 공식 API
계약에 strict integrity 보장이 없고 실제 관찰이 fail-open 가능성을 보였다는 이유로, 독립 검증 전
Deflate를 정상·손상 모두 격리했습니다. 2026-08-09에는 독립 validator를 추가해 검사를 통과한 정상
입력만 WIC에 전달하도록 이 임시 결정을 대체했습니다.

## 저작권과 구현 provenance

TIFF 6.0 문서에는 문서 복사 조건이 별도로 적혀 있습니다. 저장소에는 규격 문장, pseudocode, 도표나
sample binary를 복사하지 않았고 형식 규칙을 읽어 새 C++ 상태 기계를 독립 구현했습니다. libtiff, zlib,
GIF decoder나 다른 프로젝트의 LZW source를 복사·번역하지 않았습니다.

LZW 검사기는 문자열을 보유하지 않고 사전 entry 길이만 계산합니다. Deflate 검사기는 checksum과
back-reference 검증에 필요한 32 KiB sliding window만 보유합니다. 합성 TIFF와 Deflate stream도 test
코드가 직접 구성하며 외부 사진·ICC·binary corpus를 저장소에 추가하지
않습니다. 사용자 TIFF는 명시된 개발 검증 범위에서 원본 위치를 read-only로 읽고 이름·경로·hash를
tracked 문서에 남기지 않았습니다.

## 제한적 특허 화면

- [US4558302A](https://patents.google.com/patent/US4558302A/en)는 원 LZW 계열 문헌입니다. Google Patents는
  `Expired - Lifetime`과 2003년 예상 만료를 표시하지만 법적 결론이 아니라 공개 metadata로만 취급합니다.
- [US10462164B2](https://patents.google.com/patent/US10462164B2/en)는 TIFF conformity와 LZW strip 검사를
  설명합니다. 공개 청구항을 제한적으로 대조했을 때 nonconforming data를 다루며 substitute electronic
  file을 생성·사용하는 결합이 핵심이고, 이번 코드는 입력을 수정·재생성·대체하지 않고 거부만 합니다.
- [US7696906B2](https://patents.google.com/patent/US7696906B2/en)는 LZW code/image bit를 제거하는 변형
  압축 구조를 다룹니다. 이번 코드는 표준 TIFF code를 제거·재배열하지 않습니다.
- [US20080279418A1](https://patents.google.com/patent/US20080279418A1/en)는 fragmented image stream의
  forensic recovery를 설명합니다. 이번 코드는 fragment 탐색·복구·결합을 수행하지 않습니다.

이 비교는 제한된 keyword·claim screen이며 특허 유효성, 관할권, 균등론이나 완전한 freedom-to-operate를
판단하지 않습니다. 제품 배포 전에는 실제 배포 지역과 최종 구현을 기준으로 별도 법률 검토가 필요합니다.

## 라이선스·의존성 결론

- 새 third-party source, library, payload와 notice 의무를 추가하지 않았습니다.
- 실제 pixel decompression은 Windows 운영체제의 Microsoft 기본 WIC가 담당합니다.
- Apache-2.0 core와 별도 GPL SANE plugin 경계에는 변화가 없습니다.
- 일반 이미지 SHA-256 기본 `끔`과 공급망 artifact hash 필수 정책도 유지합니다.
- 자체 Deflate validator를 사용하므로 zlib/libtiff runtime dependency와 관련 notice/SBOM 항목은
  추가되지 않았습니다.
