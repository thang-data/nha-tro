enum RoomStatus { vacant, reserved, occupied, maintenance, inactive, expired }

extension RoomStatusLabel on RoomStatus {
  String get label => switch (this) {
    RoomStatus.vacant => 'Trống',
    RoomStatus.reserved => 'Đã đặt cọc',
    RoomStatus.occupied => 'Đang thuê',
    RoomStatus.maintenance => 'Bảo trì',
    RoomStatus.inactive => 'Ngừng cho thuê',
    RoomStatus.expired => 'Hết hạn',
  };
}

enum MeterKind { electric, water }

enum ReadingStatus { draft, confirmed }

/// monthly: đơn giá × số lượng mỗi kỳ. fixed: đơn giá một lần mỗi kỳ, số lượng luôn 1.
enum ServiceUnit { monthly, fixed }

/// Hạn thanh toán mặc định (ngày kể từ ngày 1 của kỳ) và giới hạn hợp lệ.
const int defaultPaymentDueDays = 7;
const int minPaymentDueDays = 1;
const int maxPaymentDueDays = 60;

/// Tên field Dart theo camelCase; key JSON theo snake_case để khớp backend.
class Site {
  const Site({
    required this.id,
    required this.name,
    required this.address,
    this.electricRate = 0,
    this.waterRate = 0,
  });

  final String id;
  final String name;
  final String address;

  /// Đơn giá điện (đ/kWh) và nước (đ/m³) của cơ sở. 0 nghĩa là chưa cấu hình.
  final int electricRate;
  final int waterRate;

  Site copyWith({
    String? name,
    String? address,
    int? electricRate,
    int? waterRate,
  }) => Site(
    id: id,
    name: name ?? this.name,
    address: address ?? this.address,
    electricRate: electricRate ?? this.electricRate,
    waterRate: waterRate ?? this.waterRate,
  );

  factory Site.fromJson(Map<String, dynamic> json) => Site(
    id: json['id'] as String,
    name: json['name'] as String,
    address: json['address'] as String,
    electricRate: (json['electric_rate'] as int?) ?? 0,
    waterRate: (json['water_rate'] as int?) ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'address': address,
    'electric_rate': electricRate,
    'water_rate': waterRate,
  };
}

class Room {
  const Room({
    required this.id,
    required this.siteId,
    required this.code,
    required this.floor,
    required this.status,
    required this.rent,
    this.tenantName,
    this.paymentDueDays = defaultPaymentDueDays,
  });

  final String id;
  final String siteId;
  final String code;
  final int floor;
  final RoomStatus status;
  final int rent;
  final String? tenantName;

  /// Số ngày kể từ ngày 1 của kỳ đến hạn thanh toán, cấu hình theo từng phòng.
  final int paymentDueDays;

  Room copyWith({
    RoomStatus? status,
    String? tenantName,
    bool clearTenant = false,
    int? rent,
    int? paymentDueDays,
  }) => Room(
    id: id,
    siteId: siteId,
    code: code,
    floor: floor,
    status: status ?? this.status,
    rent: rent ?? this.rent,
    tenantName: clearTenant ? null : (tenantName ?? this.tenantName),
    paymentDueDays: paymentDueDays ?? this.paymentDueDays,
  );

  factory Room.fromJson(Map<String, dynamic> json) => Room(
    id: json['id'] as String,
    siteId: json['site_id'] as String,
    code: json['room_code'] as String,
    floor: json['floor'] as int,
    status: RoomStatus.values.byName(json['status'] as String),
    rent: json['rent'] as int,
    tenantName: json['tenant_name'] as String?,
    paymentDueDays: (json['payment_due_days'] as int?) ?? defaultPaymentDueDays,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'site_id': siteId,
    'room_code': code,
    'floor': floor,
    'status': status.name,
    'rent': rent,
    'tenant_name': tenantName,
    'payment_due_days': paymentDueDays,
  };
}

class Service {
  const Service({
    required this.id,
    required this.siteId,
    required this.name,
    required this.unitPrice,
    required this.unit,
    required this.active,
  });

  final String id;
  final String siteId;
  final String name;
  final int unitPrice;
  final ServiceUnit unit;
  final bool active;

  Service copyWith({
    String? name,
    int? unitPrice,
    ServiceUnit? unit,
    bool? active,
  }) => Service(
    id: id,
    siteId: siteId,
    name: name ?? this.name,
    unitPrice: unitPrice ?? this.unitPrice,
    unit: unit ?? this.unit,
    active: active ?? this.active,
  );

  factory Service.fromJson(Map<String, dynamic> json) => Service(
    id: json['id'] as String,
    siteId: json['site_id'] as String,
    name: json['name'] as String,
    unitPrice: json['unit_price'] as int,
    unit: ServiceUnit.values.byName(json['unit'] as String),
    active: json['active'] as bool,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'site_id': siteId,
    'name': name,
    'unit_price': unitPrice,
    'unit': unit.name,
    'active': active,
  };
}

/// Dịch vụ đã gắn vào một phòng, kèm số lượng riêng của phòng đó.
class RoomService {
  const RoomService({
    required this.id,
    required this.roomId,
    required this.serviceId,
    required this.quantity,
  });

  final String id;
  final String roomId;
  final String serviceId;
  final int quantity;

  factory RoomService.fromJson(Map<String, dynamic> json) => RoomService(
    id: json['id'] as String,
    roomId: json['room_id'] as String,
    serviceId: json['service_id'] as String,
    quantity: json['quantity'] as int,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'room_id': roomId,
    'service_id': serviceId,
    'quantity': quantity,
  };
}

class Tenant {
  const Tenant({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.citizenId,
  });

  final String id;
  final String fullName;
  final String phone;
  final String citizenId;

  factory Tenant.fromJson(Map<String, dynamic> json) => Tenant(
    id: json['id'] as String,
    fullName: json['full_name'] as String,
    phone: json['phone'] as String,
    citizenId: json['citizen_id'] as String,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'full_name': fullName,
    'phone': phone,
    'citizen_id': citizenId,
  };
}

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class Contract {
  const Contract({
    required this.id,
    required this.roomId,
    required this.tenantId,
    required this.startDate,
    required this.rent,
    this.deposit = 0,
    this.endedAt,
  });

  final String id;
  final String roomId;
  final String tenantId;
  final DateTime startDate;
  final int rent;

  /// Tiền cọc ghi trên hợp đồng. Khi thanh lý sẽ được trừ vào hóa đơn thanh lý.
  final int deposit;

  /// Ngày thanh lý. Null nghĩa là hợp đồng còn hiệu lực.
  final DateTime? endedAt;

  bool get isActive => endedAt == null;

  Contract copyWith({int? rent, int? deposit}) => Contract(
    id: id,
    roomId: roomId,
    tenantId: tenantId,
    startDate: startDate,
    rent: rent ?? this.rent,
    deposit: deposit ?? this.deposit,
    endedAt: endedAt,
  );

  Contract ended(DateTime at) => Contract(
    id: id,
    roomId: roomId,
    tenantId: tenantId,
    startDate: startDate,
    rent: rent,
    deposit: deposit,
    endedAt: at,
  );

  factory Contract.fromJson(Map<String, dynamic> json) => Contract(
    id: json['id'] as String,
    roomId: json['room_id'] as String,
    tenantId: json['tenant_id'] as String,
    startDate: DateTime.parse(json['start_date'] as String),
    rent: json['rent'] as int,
    deposit: (json['deposit'] as int?) ?? 0,
    endedAt: json['ended_at'] == null
        ? null
        : DateTime.parse(json['ended_at'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'room_id': roomId,
    'tenant_id': tenantId,
    'start_date': isoDate(startDate),
    'rent': rent,
    'deposit': deposit,
    'status': isActive ? 'active' : 'ended',
    'ended_at': endedAt?.toIso8601String(),
  };
}

enum PhotoKind { inspection, liquidation, paymentProof }

/// Ảnh nén (JPEG, base64) lưu trực tiếp trong Firestore, mỗi ảnh một document.
class Photo {
  const Photo({
    required this.id,
    required this.siteId,
    required this.kind,
    required this.data,
    required this.createdAt,
    this.roomId = '',
    this.contractId = '',
    this.invoiceId = '',
  });

  final String id;
  final String siteId;
  final PhotoKind kind;

  /// Nội dung JPEG đã mã hóa base64.
  final String data;
  final DateTime createdAt;
  final String roomId;
  final String contractId;
  final String invoiceId;

  factory Photo.fromJson(Map<String, dynamic> json) => Photo(
    id: json['id'] as String,
    siteId: json['site_id'] as String,
    kind: PhotoKind.values.byName(json['kind'] as String),
    data: json['data'] as String,
    createdAt: DateTime.parse(json['created_at'] as String),
    roomId: (json['room_id'] as String?) ?? '',
    contractId: (json['contract_id'] as String?) ?? '',
    invoiceId: (json['invoice_id'] as String?) ?? '',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'site_id': siteId,
    'kind': kind.name,
    'data': data,
    'created_at': createdAt.toIso8601String(),
    'room_id': roomId,
    'contract_id': contractId,
    'invoice_id': invoiceId,
  };
}

class MeterReading {
  const MeterReading({
    required this.id,
    required this.roomId,
    required this.period,
    required this.kind,
    required this.startValue,
    required this.endValue,
    required this.status,
  });

  final String id;
  final String roomId;
  final String period;
  final MeterKind kind;
  final int startValue;
  final int endValue;
  final ReadingStatus status;

  int get consumption => endValue - startValue;

  MeterReading copyWith({ReadingStatus? status}) => MeterReading(
    id: id,
    roomId: roomId,
    period: period,
    kind: kind,
    startValue: startValue,
    endValue: endValue,
    status: status ?? this.status,
  );

  factory MeterReading.fromJson(Map<String, dynamic> json) => MeterReading(
    id: json['id'] as String,
    roomId: json['room_id'] as String,
    period: json['period'] as String,
    kind: MeterKind.values.byName(json['kind'] as String),
    startValue: json['start_value'] as int,
    endValue: json['end_value'] as int,
    status: ReadingStatus.values.byName(json['status'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'room_id': roomId,
    'period': period,
    'kind': kind.name,
    'start_value': startValue,
    'end_value': endValue,
    'status': status.name,
  };
}

class Payment {
  const Payment({
    required this.id,
    required this.invoiceId,
    required this.amount,
    required this.method,
    required this.paidAt,
    required this.idempotencyKey,
    this.reference,
    this.proofPhotoId,
  });

  /// Method 'settlement': khoản nợ được chuyển sang hóa đơn thanh lý (reference là id hóa đơn đó).
  static const settlementMethod = 'settlement';

  final String id;
  final String invoiceId;
  final int amount;

  /// 'cash', 'transfer' hoặc 'settlement'.
  final String method;
  final String? reference;
  final DateTime paidAt;
  final String idempotencyKey;

  /// Id ảnh chứng từ chuyển khoản (collection photos), nếu có.
  final String? proofPhotoId;

  factory Payment.fromJson(Map<String, dynamic> json) => Payment(
    id: json['id'] as String,
    invoiceId: json['invoice_id'] as String,
    amount: json['amount'] as int,
    method: json['method'] as String,
    reference: json['reference'] as String?,
    paidAt: DateTime.parse(json['paid_at'] as String),
    idempotencyKey: json['idempotency_key'] as String,
    proofPhotoId: json['proof_photo_id'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'invoice_id': invoiceId,
    'amount': amount,
    'method': method,
    'reference': reference,
    'paid_at': paidAt.toIso8601String(),
    'idempotency_key': idempotencyKey,
    'proof_photo_id': proofPhotoId,
  };
}

enum InvoiceStatus { unpaid, partial, paid, overdue }

/// Một dòng trong hóa đơn: tiền phòng, điện, nước hoặc từng dịch vụ.
class InvoiceLine {
  const InvoiceLine({
    required this.label,
    required this.description,
    required this.amount,
    this.section,
    this.unitPrice,
    this.details = const [],
  });

  final String label;

  /// Công thức hiển thị, ví dụ '120 kWh × 3.500 đ'. Rỗng nếu không cần.
  final String description;
  final int amount;

  /// Nhóm hiển thị trên hóa đơn, ví dụ 'Tiền điện'. Null thì dùng [label].
  final String? section;

  /// Đơn giá của khoản thu, nếu có (tiền phòng, điện, nước).
  final int? unitPrice;

  /// Dòng chi tiết, ví dụ chỉ số đầu kỳ, cuối kỳ và tiêu thụ.
  final List<InvoiceDetail> details;

  factory InvoiceLine.fromJson(Map<String, dynamic> json) => InvoiceLine(
    label: json['label'] as String,
    description: json['description'] as String? ?? '',
    amount: json['amount'] as int,
    section: json['section'] as String?,
    unitPrice: json['unit_price'] as int?,
    details: [
      for (final d in (json['details'] as List?) ?? const [])
        InvoiceDetail.fromJson(d as Map<String, dynamic>),
    ],
  );

  Map<String, dynamic> toJson() => {
    'label': label,
    'description': description,
    'amount': amount,
    'section': section,
    'unit_price': unitPrice,
    'details': [for (final d in details) d.toJson()],
  };
}

/// Một dòng chi tiết của khoản thu, ví dụ ('Đầu kỳ', '10.536').
class InvoiceDetail {
  const InvoiceDetail({required this.label, required this.value});

  final String label;
  final String value;

  factory InvoiceDetail.fromJson(Map<String, dynamic> json) => InvoiceDetail(
    label: json['label'] as String,
    value: json['value'] as String,
  );

  Map<String, dynamic> toJson() => {'label': label, 'value': value};
}

class Invoice {
  const Invoice({
    required this.id,
    required this.roomCode,
    required this.tenant,
    required this.period,
    required this.total,
    required this.dueDate,
    this.siteId = '',
    this.payments = const [],
    this.lines = const [],
  });

  final String id;

  /// Cơ sở của phòng, dùng để giới hạn quyền nhân viên.
  final String siteId;
  final String roomCode;
  final String tenant;
  final String period;
  final int total;
  final DateTime dueDate;
  final List<Payment> payments;

  /// Chi tiết cấu thành tổng hóa đơn. Tổng các dòng phải bằng [total].
  final List<InvoiceLine> lines;

  int get paid => payments.fold(0, (s, p) => s + p.amount);

  int get remaining {
    final r = total - paid;
    return r > 0 ? r : 0;
  }

  /// Quá hạn được suy ra từ hạn thanh toán và số còn nợ, không lưu cứng.
  InvoiceStatus statusAt(DateTime now) {
    if (remaining == 0) return InvoiceStatus.paid;
    final today = DateTime(now.year, now.month, now.day);
    if (today.isAfter(dueDate)) return InvoiceStatus.overdue;
    return paid > 0 ? InvoiceStatus.partial : InvoiceStatus.unpaid;
  }

  Invoice copyWith({
    List<Payment>? payments,
    List<InvoiceLine>? lines,
    int? total,
  }) => Invoice(
    id: id,
    siteId: siteId,
    roomCode: roomCode,
    tenant: tenant,
    period: period,
    total: total ?? this.total,
    dueDate: dueDate,
    payments: payments ?? this.payments,
    lines: lines ?? this.lines,
  );

  factory Invoice.fromJson(Map<String, dynamic> json) => Invoice(
    id: json['id'] as String,
    siteId: json['site_id'] as String? ?? '',
    roomCode: json['room_code'] as String,
    tenant: json['tenant_name'] as String,
    period: json['period'] as String,
    total: json['total'] as int,
    dueDate: DateTime.parse(json['due_date'] as String),
    payments: [
      for (final p in json['payments'] as List)
        Payment.fromJson(p as Map<String, dynamic>),
    ],
    lines: [
      for (final l in (json['lines'] as List?) ?? const [])
        InvoiceLine.fromJson(l as Map<String, dynamic>),
    ],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'site_id': siteId,
    'room_code': roomCode,
    'tenant_name': tenant,
    'period': period,
    'total': total,
    'due_date': isoDate(dueDate),
    'payments': [for (final p in payments) p.toJson()],
    'lines': [for (final l in lines) l.toJson()],
  };
}

class ActivityEntry {
  const ActivityEntry({
    required this.time,
    required this.actor,
    required this.action,
  });

  final DateTime time;
  final String actor;
  final String action;

  factory ActivityEntry.fromJson(Map<String, dynamic> json) => ActivityEntry(
    time: DateTime.parse(json['time'] as String),
    actor: json['actor'] as String,
    action: json['action'] as String,
  );

  Map<String, dynamic> toJson() => {
    'time': time.toIso8601String(),
    'actor': actor,
    'action': action,
  };
}

/// Các loại chi phí của cơ sở.
const expenseCategories = [
  'Sửa chữa',
  'Điện nước trả chủ',
  'Lương nhân viên',
  'Vệ sinh',
  'Khác',
];

/// Khoản chi phí của một cơ sở. Chỉ super admin ghi nhận, dùng để tính lợi nhuận.
class Expense {
  const Expense({
    required this.id,
    required this.siteId,
    required this.date,
    required this.category,
    required this.amount,
    required this.note,
  });

  final String id;
  final String siteId;
  final DateTime date;
  final String category;
  final int amount;
  final String note;

  factory Expense.fromJson(Map<String, dynamic> json) => Expense(
    id: json['id'] as String,
    siteId: json['site_id'] as String,
    date: DateTime.parse(json['date'] as String),
    category: json['category'] as String,
    amount: json['amount'] as int,
    note: json['note'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'site_id': siteId,
    'date': isoDate(date),
    'category': category,
    'amount': amount,
    'note': note,
  };
}
