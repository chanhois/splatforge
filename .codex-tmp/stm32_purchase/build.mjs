import fs from "node:fs/promises";
import { Workbook, SpreadsheetFile } from "@oai/artifact-tool";

const outputDir = "/Users/seochanho/repositories/splatforge/outputs/019fef76-0154-73e1-a2bd-400ed23cd526";
const workbook = Workbook.create();
const list = workbook.worksheets.add("STM32 구매 목록");
const guide = workbook.worksheets.add("작성 가이드");

list.showGridLines = false;
list.mergeCells("A1:K1");
list.getRange("A1").values = [["STM32 개발용 구매 목록"]];
list.getRange("A1:K1").format = { fill: "#16324F", font: { color: "#FFFFFF", bold: true, size: 18 }, verticalAlignment: "center" };
list.getRange("A1:K1").format.rowHeight = 34;
list.mergeCells("A2:K2");
list.getRange("A2").values = [["범용 STM32 개발 세트 기준 · 단가는 예상가이므로 발주 전 판매처에서 확인하세요."]];
list.getRange("A2:K2").format = { fill: "#EAF2F8", font: { color: "#425466", italic: true }, verticalAlignment: "center" };
list.getRange("A2:K2").format.rowHeight = 26;

list.getRange("A4:B8").values = [
  ["요약", "금액/건수"],
  ["총 예상 금액", null],
  ["구매 완료 금액", null],
  ["미구매 금액", null],
  ["전체 품목 수", null],
];
list.getRange("B5").formulas = [["=SUM(H12:H28)"]];
list.getRange("B6").formulas = [["=SUMIF(J12:J28,\"구매 완료\",H12:H28)"]];
list.getRange("B7").formulas = [["=SUM(H12:H28)-B6"]];
list.getRange("B8").formulas = [["=COUNTA(B12:B28)"]];
list.getRange("A4:B4").format = { fill: "#2E5D7B", font: { color: "#FFFFFF", bold: true }, horizontalAlignment: "center" };
list.getRange("A5:A8").format = { fill: "#F1F5F9", font: { bold: true, color: "#334155" } };
list.getRange("B5:B7").format = { fill: "#FFF7E6", font: { bold: true, color: "#9A6700" }, numberFormat: "₩#,##0" };
list.getRange("B8").format = { fill: "#F0FDF4", font: { bold: true, color: "#166534" }, numberFormat: "#,##0\"개\"" };
list.getRange("A4:B8").format.borders = { preset: "outside", style: "thin", color: "#CBD5E1" };

const headers = [["구분", "품목명", "권장 모델/사양", "용도", "수량", "단위", "예상 단가", "예상 금액", "우선순위", "구매 상태", "비고/구매처"]];
list.getRange("A11:K11").values = headers;
const rows = [
  ["개발보드", "STM32 Nucleo 보드", "NUCLEO-F446RE", "메인 개발 및 프로토타이핑", 2, "개", 35000, null, "필수", "미구매", "공식 디스트리뷰터 권장"],
  ["개발보드", "STM32 Discovery 보드", "STM32F407G-DISC1", "LCD/오디오 및 고성능 예제", 1, "개", 45000, null, "권장", "미구매", "대체: NUCLEO-F429ZI"],
  ["디버깅", "ST-LINK 디버거", "ST-LINK/V3MINIE", "외부 보드 SWD 디버깅", 1, "개", 55000, null, "필수", "미구매", "정품 권장"],
  ["디버깅", "SWD 케이블", "10핀 1.27 mm ↔ 2.54 mm", "타깃 보드 연결", 2, "개", 8000, null, "필수", "미구매", "핀 배열 확인"],
  ["전원", "벤치 전원공급기", "0–30 V / 0–5 A, 전류 제한", "안정적인 실험 전원", 1, "대", 120000, null, "권장", "미구매", "보유 시 제외"],
  ["전원", "USB-C 전원 어댑터", "5 V / 3 A", "보드 및 주변장치 전원", 2, "개", 15000, null, "필수", "미구매", "KC 인증 제품"],
  ["케이블", "USB 데이터 케이블", "USB-A↔Micro-B / USB-C", "다운로드 및 시리얼 통신", 3, "개", 7000, null, "필수", "미구매", "충전 전용 케이블 제외"],
  ["프로토타이핑", "브레드보드", "830 tie-points", "회로 프로토타이핑", 2, "개", 9000, null, "필수", "미구매", "전원 레일 포함"],
  ["프로토타이핑", "점퍼 와이어 세트", "M-M / M-F / F-F", "보드 및 센서 배선", 3, "세트", 6000, null, "필수", "미구매", "각 타입 1세트"],
  ["부품", "저항 키트", "1 Ω–1 MΩ, 1/4 W", "풀업/분압/LED 제한", 1, "세트", 18000, null, "필수", "미구매", "E12 또는 E24"],
  ["부품", "커패시터 키트", "세라믹 + 전해", "디커플링 및 필터", 1, "세트", 22000, null, "필수", "미구매", "100 nF 포함"],
  ["부품", "LED 및 택트 스위치", "3 mm/5 mm LED, 6×6 mm 스위치", "GPIO 입출력 테스트", 1, "세트", 12000, null, "권장", "미구매", "색상 혼합"],
  ["통신", "USB-UART 변환기", "3.3 V TTL, CP2102/FT232", "로그 및 UART 통신", 2, "개", 12000, null, "필수", "미구매", "5 V 출력 주의"],
  ["센서", "기본 센서 모듈", "I²C/SPI: 온습도, IMU", "주변장치 통신 실습", 1, "세트", 35000, null, "선택", "미구매", "3.3 V 호환"],
  ["측정", "디지털 멀티미터", "DC V/A, 저항, 연속성", "기본 전기 측정", 1, "대", 50000, null, "필수", "미구매", "보유 시 제외"],
  ["측정", "로직 애널라이저", "8채널 24 MHz급", "UART/I²C/SPI 분석", 1, "대", 25000, null, "권장", "미구매", "PulseView 호환"],
  ["소모품", "핀헤더 및 만능기판", "2.54 mm 헤더/양면 기판", "확장 및 납땜 제작", 1, "세트", 20000, null, "권장", "미구매", "납땜 도구 보유 전제"],
];
list.getRange("A12:K28").values = rows;
list.getRange("H12").formulas = [["=E12*G12"]];
list.getRange("H12:H28").fillDown();

list.getRange("A11:K11").format = { fill: "#2E5D7B", font: { color: "#FFFFFF", bold: true }, horizontalAlignment: "center", verticalAlignment: "center", wrapText: true };
list.getRange("A12:K28").format = { font: { color: "#243B53", size: 10 }, verticalAlignment: "center" };
list.getRange("G12:H28").format.numberFormat = "₩#,##0";
list.getRange("E12:E28").format.numberFormat = "#,##0";
list.getRange("E12:J28").format.horizontalAlignment = "center";
list.getRange("D12:D28").format.wrapText = true;
list.getRange("K12:K28").format.wrapText = true;
list.getRange("A11:K28").format.borders = { insideHorizontal: { style: "thin", color: "#D8E1E8" }, bottom: { style: "thin", color: "#94A3B8" } };
list.getRange("A12:K28").conditionalFormats.addCustom("=MOD(ROW(),2)=0", { fill: "#F8FAFC" });
list.getRange("I12:I28").conditionalFormats.add("containsText", { text: "필수", format: { fill: "#FEE2E2", font: { color: "#991B1B", bold: true } } });
list.getRange("I12:I28").conditionalFormats.add("containsText", { text: "권장", format: { fill: "#FEF3C7", font: { color: "#92400E" } } });
list.getRange("J12:J28").conditionalFormats.add("containsText", { text: "구매 완료", format: { fill: "#DCFCE7", font: { color: "#166534", bold: true } } });
list.getRange("I12:I28").dataValidation = { rule: { type: "list", values: ["필수", "권장", "선택"] } };
list.getRange("J12:J28").dataValidation = { rule: { type: "list", values: ["미구매", "주문 완료", "구매 완료"] } };
list.tables.add("A11:K28", true, "STM32PurchaseTable").style = "TableStyleMedium2";
list.freezePanes.freezeRows(11);

const widths = { A: 14, B: 23, C: 28, D: 27, E: 8, F: 8, G: 14, H: 15, I: 11, J: 13, K: 27 };
for (const [col, width] of Object.entries(widths)) list.getRange(`${col}:${col}`).format.columnWidth = width;
list.getRange("11:11").format.rowHeight = 32;
list.getRange("12:28").format.rowHeight = 34;

guide.showGridLines = false;
guide.mergeCells("A1:F1");
guide.getRange("A1").values = [["STM32 구매 목록 사용 가이드"]];
guide.getRange("A1:F1").format = { fill: "#16324F", font: { color: "#FFFFFF", bold: true, size: 18 }, verticalAlignment: "center" };
guide.getRange("A1:F1").format.rowHeight = 34;
guide.getRange("A3:B8").values = [
  ["항목", "설명"],
  ["예상 단가", "발주 전 실제 판매가와 재고를 확인한 뒤 수정합니다."],
  ["예상 금액", "수량 × 예상 단가로 자동 계산됩니다."],
  ["우선순위", "필수 / 권장 / 선택 중 드롭다운으로 지정합니다."],
  ["구매 상태", "미구매 / 주문 완료 / 구매 완료 중 선택합니다."],
  ["모델 선택", "STM32CubeIDE 및 필요한 주변장치와의 호환성을 먼저 확인합니다."],
];
guide.getRange("A3:B3").format = { fill: "#2E5D7B", font: { color: "#FFFFFF", bold: true }, horizontalAlignment: "center" };
guide.getRange("A4:A8").format = { fill: "#EAF2F8", font: { bold: true, color: "#334155" } };
guide.getRange("A3:B8").format.borders = { preset: "all", style: "thin", color: "#CBD5E1" };
guide.getRange("A3:B8").format.wrapText = true;
guide.getRange("A:A").format.columnWidth = 18;
guide.getRange("B:B").format.columnWidth = 68;
guide.getRange("4:8").format.rowHeight = 36;
guide.getRange("A10:F10").merge();
guide.getRange("A10").values = [["주의: 이 파일의 가격은 예산 수립용 예상치이며 실시간 견적이 아닙니다."]];
guide.getRange("A10:F10").format = { fill: "#FFF7E6", font: { color: "#9A6700", bold: true }, wrapText: true };
guide.getRange("A10:F10").format.rowHeight = 30;

await fs.mkdir(outputDir, { recursive: true });
const check = await workbook.inspect({ kind: "table", range: "'STM32 구매 목록'!A4:K28", include: "values,formulas", tableMaxRows: 30, tableMaxCols: 12, maxChars: 9000 });
console.log("CHECK\n" + check.ndjson);
const errors = await workbook.inspect({ kind: "match", searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A", options: { useRegex: true, maxResults: 100 }, summary: "formula error scan" });
console.log("ERRORS\n" + errors.ndjson);
for (const sheetName of ["STM32 구매 목록", "작성 가이드"]) {
  const preview = await workbook.render({ sheetName, autoCrop: "all", scale: 1.5, format: "png" });
  await fs.writeFile(`${outputDir}/${sheetName}.png`, new Uint8Array(await preview.arrayBuffer()));
}
const output = await SpreadsheetFile.exportXlsx(workbook);
await output.save(`${outputDir}/STM32_구매_목록.xlsx`);
console.log(`${outputDir}/STM32_구매_목록.xlsx`);
