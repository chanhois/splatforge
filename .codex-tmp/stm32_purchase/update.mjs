import fs from "node:fs/promises";
import { Workbook, SpreadsheetFile } from "@oai/artifact-tool";

const outputDir = "/Users/seochanho/repositories/splatforge/outputs/019fef76-0154-73e1-a2bd-400ed23cd526";
const wb = Workbook.create();
const buy = wb.worksheets.add("구매 대상");
const owned = wb.worksheets.add("보유품 및 제외품");
const guide = wb.worksheets.add("구매 가이드");
const imuStock = wb.worksheets.add("IMU 재고 검증");
const sourceNote = "/Users/seochanho/Documents/Obsidian Vault/Codex/STM32 Board Trigger Time Sync.md";

const navy = "#16324F", blue = "#2E5D7B", pale = "#EAF2F8", line = "#CBD5E1";
for (const s of [buy, owned, guide, imuStock]) s.showGridLines = false;

buy.mergeCells("A1:L1");
buy.getRange("A1").values = [["STM32 Trigger Time Sync 구매 목록"]];
buy.getRange("A1:L1").format = { fill: navy, font: { color: "#FFFFFF", bold: true, size: 18 }, verticalAlignment: "center" };
buy.getRange("A1:L1").format.rowHeight = 34;
buy.mergeCells("A2:L2");
buy.getRange("A2").values = [["STM32F103C8T6 Blue Pill 기반 · 외부 CLK 지원 IMU 재고 반영 · 2026-08-14 업데이트"]];
buy.getRange("A2:L2").format = { fill: pale, font: { color: "#425466", italic: true }, verticalAlignment: "center" };
buy.getRange("A2:L2").format.rowHeight = 26;

buy.getRange("A4:B9").values = [["요약", "금액/건수"], ["전체 예상 금액", null], ["지금 구매 예상 금액", null], ["Stage 2 예상 금액", null], ["구매 완료 금액", null], ["구매 대상 품목", null]];
buy.getRange("B5").formulas = [["=SUM(I13:I18)"]];
buy.getRange("B6").formulas = [["=SUMIF(B13:B18,\"지금 구매\",I13:I18)"]];
buy.getRange("B7").formulas = [["=SUMIF(B13:B18,\"Stage 2\",I13:I18)"]];
buy.getRange("B8").formulas = [["=SUMIF(K13:K18,\"구매 완료\",I13:I18)"]];
buy.getRange("B9").formulas = [["=COUNTA(C13:C18)"]];
buy.getRange("A4:B4").format = { fill: blue, font: { color: "#FFFFFF", bold: true }, horizontalAlignment: "center" };
buy.getRange("A5:A9").format = { fill: "#F1F5F9", font: { bold: true, color: "#334155" } };
buy.getRange("B5:B8").format = { fill: "#FFF7E6", font: { bold: true, color: "#9A6700" }, numberFormat: "₩#,##0" };
buy.getRange("B9").format = { fill: "#F0FDF4", font: { bold: true, color: "#166534" }, numberFormat: "#,##0\"개\"" };
buy.getRange("A4:B9").format.borders = { preset: "outside", style: "thin", color: line };
buy.getRange("A:A").format.columnWidth = 22;
buy.getRange("B:B").format.columnWidth = 16;

buy.getRange("A12:L12").values = [["번호", "구매 시점", "품목", "권장 모델/필수 조건", "수량", "단위", "용도", "예상 단가", "예상 금액", "우선순위", "구매 상태", "비고"]];
buy.getRange("A13:L18").values = [
  [1, "지금 구매", "TDK QCIOT-ICM42688P Pmod evaluation board", "ICM-42688-P 조립 Pmod, 3.3 V·SPI, INT1 DRDY, INT2/CLKIN 헤더 노출", 1, "개", "외부 32 kHz reference clock 기반 IMU sampling과 DRDY capture", 74147, null, "필수", "미구매", "Mouser Korea 개별 페이지: 60개 즉시배송·₩74,147 (2026-08-12 확인); J3 SPI shunt 4개 포함, 결제 직전 재확인"],
  [2, "Stage 2", "Analog electret microphone amplifier", "Analog OUT, MAX4466 계열 권장; I²S/PDM digital mic 제외", 1, "개", "Audio event capture", 15000, null, "필수", "대기", "Stage 2 진입 시 구매"],
  [3, "Stage 2", "D435 9-pin hardware-sync cable/connector", "완제품 또는 JST SHR-09V-S housing + 호환 contact/wire", 1, "식", "STM32 trigger와 D435 연결", 15000, null, "필수", "대기", "sync 회로와 pinout 확정 후 구매"],
  [4, "Stage 2", "3.3 V → 1.8 V level conversion 부품", "단방향 level shifter 또는 검증된 resistor divider", 1, "식", "D435 1.8 V HW_SYNC 입력 보호", 5000, null, "필수", "대기", "Blue Pill GPIO 직접 연결 금지"],
  [5, "Stage 2", "Buzzer transistor driver 부품", "NPN 2N2222/S8050, base 1 kΩ, magnetic buzzer면 flyback diode", 1, "식", "GPIO 보호와 marker buzzer 구동", 3000, null, "권장", "대기", "보유 부품으로 구성 가능하면 구매 제외"],
  [6, "Stage 2", "Local decoupling capacitor", "100 nF와 10 µF 각 2개 이상", 1, "식", "IMU와 microphone 전원 잡음 억제", 3000, null, "권장", "대기", "보유 수량 확인 후 부족분만 구매"],
];
buy.getRange("I13").formulas = [["=E13*H13"]];
buy.getRange("I13:I18").fillDown();
buy.getRange("A12:L12").format = { fill: blue, font: { color: "#FFFFFF", bold: true }, horizontalAlignment: "center", verticalAlignment: "center", wrapText: true };
buy.getRange("A13:L18").format = { font: { color: "#243B53", size: 10 }, verticalAlignment: "center", wrapText: true };
buy.getRange("H13:I18").format.numberFormat = "₩#,##0";
buy.getRange("A13:B18").format.horizontalAlignment = "center";
buy.getRange("E13:F18").format.horizontalAlignment = "center";
buy.getRange("J13:K18").format.horizontalAlignment = "center";
buy.getRange("A12:L18").format.borders = { insideHorizontal: { style: "thin", color: "#D8E1E8" }, bottom: { style: "thin", color: "#94A3B8" } };
buy.getRange("B13:B18").conditionalFormats.add("containsText", { text: "지금 구매", format: { fill: "#FEE2E2", font: { color: "#991B1B", bold: true } } });
buy.getRange("B13:B18").conditionalFormats.add("containsText", { text: "Stage 2", format: { fill: "#FEF3C7", font: { color: "#92400E" } } });
buy.getRange("K13:K18").conditionalFormats.add("containsText", { text: "구매 완료", format: { fill: "#DCFCE7", font: { color: "#166534", bold: true } } });
buy.getRange("B13:B18").dataValidation = { rule: { type: "list", values: ["지금 구매", "Stage 2"] } };
buy.getRange("J13:J18").dataValidation = { rule: { type: "list", values: ["필수", "권장", "선택"] } };
buy.getRange("K13:K18").dataValidation = { rule: { type: "list", values: ["미구매", "주문 완료", "구매 완료", "대기"] } };
buy.tables.add("A12:L18", true, "ProjectPurchaseTable").style = "TableStyleMedium2";
buy.freezePanes.freezeRows(12);
const buyWidths = { A: 22, B: 16, C: 30, D: 47, E: 8, F: 8, G: 32, H: 14, I: 15, J: 11, K: 13, L: 38 };
for (const [c,w] of Object.entries(buyWidths)) buy.getRange(`${c}:${c}`).format.columnWidth = w;
buy.getRange("12:12").format.rowHeight = 32;
buy.getRange("13:18").format.rowHeight = 54;

owned.mergeCells("A1:D1"); owned.getRange("A1").values = [["보유품 및 구매 제외 판단"]];
owned.getRange("A1:D1").format = { fill: navy, font: { color: "#FFFFFF", bold: true, size: 18 }, verticalAlignment: "center" }; owned.getRange("A1:D1").format.rowHeight = 34;
owned.getRange("A3:D3").values = [["분류", "물품", "상태/판단", "프로젝트 메모"]];
owned.getRange("A4:D18").values = [
  ["보유품", "STM32F103C8T6 Blue Pill", "보유 — 구매하지 않음", "Stage 0–1 기준 보드"],
  ["보유품", "ST-Link V2", "보유 — 구매하지 않음", "현재 Mac에서 인식 여부 재확인 필요"],
  ["보유품", "USB-to-TTL serial adapter", "보유 — 구매하지 않음", "115200 baud heartbeat 확인용"],
  ["보유품", "Solderless breadboard", "보유 — 구매하지 않음", "SPI prototype"],
  ["보유품", "Dupont jumper wire 세트", "보유 — 구매하지 않음", "QCIOT Pmod J1/J2와 Blue Pill 연결에 female-to-female 8가닥 사용"],
  ["보유품", "Marker LED와 저항", "보유 — 구매하지 않음", "trigger 표시"],
  ["보유품", "Buzzer 부품", "보유 — 구매하지 않음", "event 표시"],
  ["구매 완료", "8-channel USB logic analyzer", "구매 완료 (2026-08-11)", "32 kHz CLKIN, DRDY, SPI, D435 trigger 계측"],
  ["구매 완료", "Intel RealSense D435", "구매 완료 (2026-08-11)", "USB 3 단독 동작 확인 후 hardware sync 연결"],
  ["보류", "Oscilloscope", "Stage 2에서 대여 우선", "trigger/strobe voltage·latency 검증"],
  ["제외", "Pmod 2.54 mm pin header와 납땜 도구", "QCIOT 조립 Pmod의 J1/J2 사용", "보유 Dupont wire로 직접 연결; 별도 interposer 불필요"],
  ["제외", "추가 STM32/Nucleo board", "현재 불필요", "Blue Pill로 Stage 0–1 진행 가능"],
  ["제외", "RealSense D435i", "구매 제외", "D435를 이미 구매했으므로 중복"],
  ["제외", "BMI088/EBIMU 계열", "이번 IMU 구매에서 제외", "외부 reference CLKIN 요구와 STM32 hardware capture 요구를 동시에 충족하지 못함"],
  ["구매 후보", "TDK QCIOT-ICM42688P", "기술 적합·즉시출하", "Mouser Korea 60개 확인; SPI·INT1·INT2/CLKIN이 Pmod 헤더에 노출"],
];
owned.getRange("A3:D3").format = { fill: blue, font: { color: "#FFFFFF", bold: true }, horizontalAlignment: "center" };
owned.getRange("A4:D18").format = { wrapText: true, verticalAlignment: "center" };
owned.getRange("A4:A18").format = { fill: pale, font: { bold: true, color: "#334155" }, horizontalAlignment: "center" };
owned.getRange("A3:D18").format.borders = { preset: "all", style: "thin", color: line };
for (const [c,w] of Object.entries({A:12,B:34,C:32,D:43})) owned.getRange(`${c}:${c}`).format.columnWidth = w;
owned.getRange("4:18").format.rowHeight = 42;
owned.freezePanes.freezeRows(3);

guide.mergeCells("A1:F1"); guide.getRange("A1").values = [["구매 및 실기 검증 가이드"]];
guide.getRange("A1:F1").format = { fill: navy, font: { color: "#FFFFFF", bold: true, size: 18 }, verticalAlignment: "center" }; guide.getRange("A1:F1").format.rowHeight = 34;
guide.getRange("A3:B10").values = [
  ["순서", "실행 내용"],
  [1, "센서 없이 Blue Pill heartbeat와 synthetic DRDY loopback을 먼저 통과시킴"],
  [2, "정확한 품번 QCIOT-ICM42688P를 주문하고 Mouser Korea 결제 화면에서 현재 재고를 다시 확인"],
  [3, "QCIOT J3의 SPI shunt 4개를 모두 1-2, 3-4, 5-6, 7-8로 장착하고 J1/J2 Type 2A SPI를 사용"],
  [4, "보유 female-to-female Dupont 8가닥으로 3V3/GND/CS/SCK/MISO/MOSI/INT1/CLKIN 연결"],
  [5, "PB6/TIM4_CH1 32 kHz 50% clock→J1/J2 pin10 INT2/CLKIN, INT1 DRDY→pin7→PA1/TIM2_CH2 input capture"],
  [6, "ICM-42688-P PIN9_FUNCTION을 CLKIN(10b)으로 설정하고 INT1에 UI data-ready interrupt를 매핑"],
  [7, "logic analyzer에서 CLKIN 32 kHz, DRDY 주기, SPI read 지연을 검증한 뒤 D435 trigger와 비교"],
];
guide.getRange("A3:B3").format = { fill: blue, font: { color: "#FFFFFF", bold: true }, horizontalAlignment: "center" };
guide.getRange("A4:A10").format = { fill: pale, font: { bold: true }, horizontalAlignment: "center" };
guide.getRange("A3:B10").format.borders = { preset: "all", style: "thin", color: line };
guide.getRange("A3:B10").format.wrapText = true;
guide.getRange("A:A").format.columnWidth = 10; guide.getRange("B:B").format.columnWidth = 110; guide.getRange("4:10").format.rowHeight = 42;
guide.mergeCells("A12:F12"); guide.getRange("A12").values = [["안전 주의: IMU는 3.3 V로만 구동하고, Blue Pill GPIO(3.3 V)는 D435 HW_SYNC 입력(1.8 V CMOS)에 직접 연결하지 않습니다."]];
guide.getRange("A12:F12").format = { fill: "#FEE2E2", font: { color: "#991B1B", bold: true }, wrapText: true }; guide.getRange("A12:F12").format.rowHeight = 34;
guide.mergeCells("A14:F14"); guide.getRange("A14").values = [[`근거 노트: ${sourceNote}`]];
guide.getRange("A14:F14").format = { fill: "#F8FAFC", font: { color: "#475569", italic: true }, wrapText: true };

imuStock.mergeCells("A1:M1");
imuStock.getRange("A1").values = [["외부 CLK 지원 IMU 재고 검증"]];
imuStock.getRange("A1:M1").format = { fill: navy, font: { color: "#FFFFFF", bold: true, size: 18 }, verticalAlignment: "center" };
imuStock.getRange("A1:M1").format.rowHeight = 34;
imuStock.mergeCells("A2:M2");
imuStock.getRange("A2").values = [["공식 센서/보드 문서와 한국 주문 가능한 판매 페이지를 교차검증 · 공개 재고 스냅샷 2026-08-12"]];
imuStock.getRange("A2:M2").format = { fill: pale, font: { color: "#425466", italic: true }, verticalAlignment: "center" };
imuStock.getRange("A2:M2").format.rowHeight = 26;
imuStock.getRange("A4:M4").values = [["순위", "정확한 품번", "판정", "센서/보드", "SPI", "DRDY", "외부 CLK/동기 입력", "조립·배선", "판매처", "공개 재고·가격", "확인일", "판매/재고 URL", "공식 기술 URL"]];
imuStock.getRange("A5:M10").values = [
  [1, "QCIOT-ICM42688P", "구매 1순위·즉시출하", "TDK QCIoT Pmod / ICM-42688-P", "예·최대 24 MHz", "J1/J2 pin7 INT1", "J1/J2 pin10 INT2/CLKIN; 31–50 kHz continuous external reference clock", "조립 Pmod Type 2A; J3 SPI shunt 4개 포함; 2.54 mm Dupont 직결", "Mouser Korea", "60개 즉시배송 · ₩74,147", "2026-08-12", "https://www.mouser.kr/ProductDetail/TDK-InvenSense/QCIOT-ICM42688P?qs=%252BXxaIXUDbq0VEyK5Yf%2FVJg%3D%3D", "https://www.mouser.com/datasheet/2/400/TDK_11_21_2024_AN_000493_QCIoT_ICM42688P_Evaluatio-3534812.pdf"],
  [2, "EV_ICM-45686", "저가 고성능 대체·즉시출하", "TDK InvenSense ICM-45686 evaluation board", "예·최대 24 MHz", "CN1 pin3 INT1", "CN1 pin6 INT2/CLKIN; 20–40 kHz continuous external clock", "조립 평가보드; CN1 jump-wire 연결, 5 V 전원·JP1/JP2 3.0 V 설정 필요", "DigiKey Korea", "39개 · ₩56,740", "2026-08-12", "https://www.digikey.kr/ko/products/detail/tdk-invensense/EV-ICM-45686/24883422", "https://invensense.tdk.com/wp-content/uploads/2024/07/AN-000478_ICM-45605-ICM-45686-User-Guide.pdf"],
  [3, "ADIS16470/PCBZ", "산업용 고급 대체", "Analog Devices ADIS16470 포함 breakout", "예·최대 2 MHz", "DR output", "SYNC direct/pulse/scaled; direct mode 외부 신호가 sample clock 직접 제어", "조립 breakout; 2x8 2 mm connector라 별도 cable/interposer 필요", "DigiKey Korea", "78개 · ₩652,955", "2026-08-12", "https://www.digikey.kr/ko/products/detail/analog-devices-inc/ADIS16470-PCBZ/7932981", "https://www.analog.com/media/en/technical-documentation/data-sheets/ADIS16470.pdf"],
  [4, "MIKROE-4237", "기술 적합·재고 없음", "Mikroe 6DOF IMU 14 Click / ICM-42688-P", "예·최대 24 MHz", "INT1", "SNC→INT2/FSYNC/CLKIN, 31–50 kHz external reference clock", "조립 Click board; 2.54 mm mikroBUS header", "Mouser Korea", "0개 · backorder · factory lead-time 7주", "2026-08-12", "https://www.mouser.kr/ProductDetail/Mikroe/MIKROE-4237?qs=hWgE7mdIu5Th0Vmu4C82%2FQ%3D%3D", "https://www.mikroe.com/6dof-imu-14-click"],
  [5, "BMI088 breakout", "외부 CLK 조건 탈락", "Bosch BMI088", "예", "INT 지원", "가속도-자이로 내부 sync는 가능하지만 센서 공통 external reference CLKIN 없음", "판매 보드별 핀 노출·납땜 상태 불일치", "복수", "구매하지 않음", "2026-08-12", "", "https://www.bosch-sensortec.com/products/motion-sensors/imus/bmi088/"],
  [6, "EBIMU-9DOFV5-R3", "인터페이스 조건 탈락", "E2BOX 완제품 AHRS", "아니오", "없음", "외부 CLK/FSYNC 없음; 내부 timestamp만 제공", "UART/USB 완제품", "DeviceMart", "VAT 포함 ₩159,500", "2026-08-12", "https://www.devicemart.co.kr/goods/view?no=12508129", "https://www.e2box.co.kr/entry/AHRS-EBIMU9DOFV5"],
];
imuStock.getRange("A4:M4").format = { fill: blue, font: { color: "#FFFFFF", bold: true }, horizontalAlignment: "center", verticalAlignment: "center", wrapText: true };
imuStock.getRange("A5:M10").format = { font: { color: "#243B53", size: 10 }, verticalAlignment: "center", wrapText: true };
imuStock.getRange("A5:C10").format.horizontalAlignment = "center";
imuStock.getRange("E5:F10").format.horizontalAlignment = "center";
imuStock.getRange("I5:K10").format.horizontalAlignment = "center";
imuStock.getRange("A4:M10").format.borders = { insideHorizontal: { style: "thin", color: "#D8E1E8" }, bottom: { style: "thin", color: "#94A3B8" } };
imuStock.getRange("C5:C10").conditionalFormats.add("containsText", { text: "구매 1순위", format: { fill: "#DCFCE7", font: { color: "#166534", bold: true } } });
imuStock.getRange("C5:C10").conditionalFormats.add("containsText", { text: "재고 없음", format: { fill: "#FEE2E2", font: { color: "#991B1B" } } });
imuStock.getRange("C5:C10").conditionalFormats.add("containsText", { text: "탈락", format: { fill: "#F1F5F9", font: { color: "#475569" } } });
imuStock.tables.add("A4:M10", true, "ImuStockValidationTable").style = "TableStyleMedium2";
imuStock.freezePanes.freezeRows(4);
const stockWidths = { A: 7, B: 24, C: 20, D: 35, E: 14, F: 12, G: 45, H: 42, I: 18, J: 26, K: 14, L: 58, M: 58 };
for (const [c,w] of Object.entries(stockWidths)) imuStock.getRange(`${c}:${c}`).format.columnWidth = w;
imuStock.getRange("4:4").format.rowHeight = 36;
imuStock.getRange("5:10").format.rowHeight = 72;
imuStock.mergeCells("A11:M12");
imuStock.getRange("A11").values = [["재고 수량과 가격은 공개 페이지 확인 시점의 스냅샷입니다. 최종 발주 전 장바구니에서 QCIOT-ICM42688P의 즉시출하 수량, 배송비와 세금을 다시 확인합니다. QCIOT 품절 시 EV_ICM-45686을 대체 후보로 검토하고, ADIS는 예산 승인 후 선택합니다."]];
imuStock.getRange("A11:M12").format = { fill: "#FFF7E6", font: { color: "#9A6700", bold: true }, wrapText: true, verticalAlignment: "center" };

await fs.mkdir(outputDir, { recursive: true });
const inspect = await wb.inspect({ kind: "table", range: "'구매 대상'!A4:L18", include: "values,formulas", tableMaxRows: 20, tableMaxCols: 12, maxChars: 8000 });
console.log("CHECK\n" + inspect.ndjson);
const stockInspect = await wb.inspect({ kind: "table", range: "'IMU 재고 검증'!A4:M12", include: "values,formulas", tableMaxRows: 12, tableMaxCols: 13, maxChars: 12000 });
console.log("STOCK_CHECK\n" + stockInspect.ndjson);
const errors = await wb.inspect({ kind: "match", searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A", options: { useRegex: true, maxResults: 100 }, summary: "formula error scan" });
console.log("ERRORS\n" + errors.ndjson);
for (const sheetName of ["구매 대상", "보유품 및 제외품", "구매 가이드", "IMU 재고 검증"]) {
  const p = await wb.render({ sheetName, autoCrop: "all", scale: 1.3, format: "png" });
  await fs.writeFile(`${outputDir}/${sheetName}_updated.png`, new Uint8Array(await p.arrayBuffer()));
}
const xlsx = await SpreadsheetFile.exportXlsx(wb);
await xlsx.save(`${outputDir}/STM32_구매_목록.xlsx`);
console.log(`${outputDir}/STM32_구매_목록.xlsx`);
