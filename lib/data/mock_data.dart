import 'models.dart';

/// Dữ liệu giả để dựng giao diện. MockRentalRepository copy các list này khi khởi tạo.
const sites = [
  Site(
    id: 's1',
    name: 'Cơ sở Cầu Giấy',
    address: '12 Trần Thái Tông, Cầu Giấy',
  ),
  Site(
    id: 's2',
    name: 'Cơ sở Thanh Xuân',
    address: '45 Nguyễn Trãi, Thanh Xuân',
  ),
];

final tenants = <Tenant>[
  const Tenant(
    id: 't-1',
    fullName: 'Nguyễn Văn An',
    phone: '0901234567',
    citizenId: '012345678901',
  ),
  const Tenant(
    id: 't-2',
    fullName: 'Trần Thị Bình',
    phone: '0912345678',
    citizenId: '098765432109',
  ),
];

final rooms = <Room>[
  const Room(
    id: 'r-A101',
    siteId: 's1',
    code: 'A101',
    floor: 1,
    status: RoomStatus.occupied,
    rent: 3000000,
    tenantName: 'Nguyễn Văn An',
  ),
  const Room(
    id: 'r-A102',
    siteId: 's1',
    code: 'A102',
    floor: 1,
    status: RoomStatus.vacant,
    rent: 2800000,
  ),
  const Room(
    id: 'r-A201',
    siteId: 's1',
    code: 'A201',
    floor: 2,
    status: RoomStatus.reserved,
    rent: 3000000,
  ),
  const Room(
    id: 'r-A202',
    siteId: 's1',
    code: 'A202',
    floor: 2,
    status: RoomStatus.maintenance,
    rent: 3200000,
  ),
  const Room(
    id: 'r-B101',
    siteId: 's2',
    code: 'B101',
    floor: 1,
    status: RoomStatus.occupied,
    rent: 2500000,
    tenantName: 'Trần Thị Bình',
  ),
  const Room(
    id: 'r-B102',
    siteId: 's2',
    code: 'B102',
    floor: 1,
    status: RoomStatus.vacant,
    rent: 2500000,
  ),
];

/// Danh mục dịch vụ theo cơ sở. Chủ trọ tự thêm/sửa/tắt trong app.
final services = <Service>[
  const Service(
    id: 'sv-1',
    siteId: 's1',
    name: 'Internet',
    unitPrice: 100000,
    unit: ServiceUnit.fixed,
    active: true,
  ),
  const Service(
    id: 'sv-2',
    siteId: 's1',
    name: 'Gửi xe',
    unitPrice: 100000,
    unit: ServiceUnit.fixed,
    active: true,
  ),
  const Service(
    id: 'sv-3',
    siteId: 's1',
    name: 'Vệ sinh',
    unitPrice: 30000,
    unit: ServiceUnit.monthly,
    active: true,
  ),
  const Service(
    id: 'sv-4',
    siteId: 's2',
    name: 'Internet',
    unitPrice: 100000,
    unit: ServiceUnit.fixed,
    active: true,
  ),
  const Service(
    id: 'sv-5',
    siteId: 's2',
    name: 'Vệ sinh',
    unitPrice: 30000,
    unit: ServiceUnit.monthly,
    active: true,
  ),
];

/// Dịch vụ đang gắn vào từng phòng.
final roomServices = <RoomService>[
  const RoomService(
    id: 'rs-1',
    roomId: 'r-A101',
    serviceId: 'sv-1',
    quantity: 1,
  ),
  const RoomService(
    id: 'rs-2',
    roomId: 'r-B101',
    serviceId: 'sv-5',
    quantity: 2,
  ),
];

final contracts = <Contract>[
  Contract(
    id: 'c-1',
    roomId: 'r-A101',
    tenantId: 't-1',
    startDate: DateTime(2026, 1, 15),
    rent: 3000000,
  ),
  Contract(
    id: 'c-2',
    roomId: 'r-B101',
    tenantId: 't-2',
    startDate: DateTime(2026, 3, 1),
    rent: 2500000,
  ),
];

final readings = <MeterReading>[
  const MeterReading(
    id: 'm-1',
    roomId: 'r-A101',
    period: 'Tháng 9/2026',
    kind: MeterKind.electric,
    startValue: 1080,
    endValue: 1200,
    status: ReadingStatus.confirmed,
  ),
  const MeterReading(
    id: 'm-2',
    roomId: 'r-A101',
    period: 'Tháng 9/2026',
    kind: MeterKind.water,
    startValue: 10,
    endValue: 18,
    status: ReadingStatus.confirmed,
  ),
];

final invoices = <Invoice>[
  Invoice(
    id: 'INV-2610-001',
    siteId: 's1',
    roomCode: 'A101',
    tenant: 'Nguyễn Văn An',
    period: 'Tháng 10/2026',
    total: 3680000,
    dueDate: DateTime(2026, 10, 27),
    lines: [
      InvoiceLine(label: 'Tiền phòng', description: '', amount: 3000000),
      InvoiceLine(
        label: 'Điện',
        description: '120 kWh × 3.500đ',
        amount: 420000,
      ),
      InvoiceLine(label: 'Nước', description: '8 m³ × 20.000đ', amount: 160000),
      InvoiceLine(label: 'Internet', description: 'Cố định', amount: 100000),
    ],
    payments: [
      Payment(
        id: 'p-1',
        invoiceId: 'INV-2610-001',
        amount: 2000000,
        method: 'cash',
        paidAt: DateTime(2026, 10, 19, 17, 40),
        idempotencyKey: 'seed-p-1',
      ),
    ],
  ),
  Invoice(
    id: 'INV-2609-014',
    roomCode: 'B101',
    tenant: 'Trần Thị Bình',
    period: 'Tháng 9/2026',
    total: 2900000,
    dueDate: DateTime(2026, 9, 27),
    lines: [
      InvoiceLine(label: 'Tiền phòng', description: '', amount: 2500000),
      InvoiceLine(
        label: 'Điện',
        description: '80 kWh × 3.500đ',
        amount: 280000,
      ),
      InvoiceLine(label: 'Nước', description: '4 m³ × 20.000đ', amount: 80000),
      InvoiceLine(label: 'Giữ xe', description: 'Cố định', amount: 40000),
    ],
  ),
  Invoice(
    id: 'INV-2610-002',
    roomCode: 'B101',
    tenant: 'Trần Thị Bình',
    period: 'Tháng 10/2026',
    total: 3100000,
    dueDate: DateTime(2026, 10, 27),
    lines: [
      InvoiceLine(label: 'Tiền phòng', description: '', amount: 2500000),
      InvoiceLine(
        label: 'Điện',
        description: '120 kWh × 3.500đ',
        amount: 420000,
      ),
      InvoiceLine(label: 'Nước', description: '6 m³ × 20.000đ', amount: 120000),
      InvoiceLine(label: 'Vệ sinh', description: '30.000đ × 2', amount: 60000),
    ],
    payments: [
      Payment(
        id: 'p-2',
        invoiceId: 'INV-2610-002',
        amount: 3100000,
        method: 'transfer',
        reference: 'FT26293001',
        paidAt: DateTime(2026, 10, 18, 10, 0),
        idempotencyKey: 'seed-p-2',
      ),
    ],
  ),
];

final activity = <ActivityEntry>[
  ActivityEntry(
    time: DateTime(2026, 10, 20, 8, 15),
    actor: 'Quản lý B',
    action: 'Điều chỉnh chỉ số A101 về 1.310 kWh (có lý do)',
  ),
  ActivityEntry(
    time: DateTime(2026, 10, 20, 8, 10),
    actor: 'Nhân viên A',
    action: 'Ghi điện A101: 1.200 → 1.320 kWh',
  ),
  ActivityEntry(
    time: DateTime(2026, 10, 20, 1, 0),
    actor: 'Hệ thống',
    action: 'Tạo hóa đơn tháng 10/2026 (12 hợp đồng)',
  ),
  ActivityEntry(
    time: DateTime(2026, 10, 19, 17, 40),
    actor: 'Nhân viên A',
    action: 'Thu 2.000.000đ phòng A101, còn nợ 1.680.000đ',
  ),
];
