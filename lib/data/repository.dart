import 'dart:convert';
import 'dart:typed_data';

import '../core/validators.dart';
import 'billing.dart';
import 'firestore_repository.dart';
import 'mock_data.dart';
import 'models.dart';

class DuplicateRoomCodeException implements Exception {
  const DuplicateRoomCodeException(this.code);
  final String code;
  @override
  String toString() => 'Mã phòng $code đã tồn tại trong cơ sở này';
}

class RoomNotAvailableException implements Exception {
  const RoomNotAvailableException();
  @override
  String toString() =>
      'Phòng đang có hợp đồng hoặc không ở trạng thái cho thuê';
}

class ServiceAlreadyAttachedException implements Exception {
  const ServiceAlreadyAttachedException();
  @override
  String toString() => 'Dịch vụ này đã gắn với phòng';
}

class PaymentExceedsRemainingException implements Exception {
  const PaymentExceedsRemainingException(this.remaining);
  final int remaining;
  @override
  String toString() => 'Số tiền thu vượt số còn nợ ($remaining)';
}

class TerminationNeedsPhotosException implements Exception {
  const TerminationNeedsPhotosException();
  @override
  String toString() =>
      'Cần ít nhất 1 ảnh kiểm tra phòng và 1 ảnh thanh lý để kết thúc hợp đồng';
}

/// Kết quả thanh lý: hợp đồng đã kết thúc và hóa đơn thanh lý (null nếu không còn gì để thu/hoàn).
class TerminationResult {
  const TerminationResult({required this.contract, this.settlement});

  final Contract contract;
  final Invoice? settlement;
}

/// Ranh giới dữ liệu của app. UI chỉ gọi qua interface này.
abstract class RentalRepository {
  Future<List<Site>> listSites();
  Future<Site> createSite({
    required String name,
    required String address,
    int electricRate = 0,
    int waterRate = 0,
  });
  Future<Site> updateSite(Site site);
  Future<List<Room>> listRooms({String? siteId, RoomStatus? status});
  Future<Room> getRoom(String id);
  Future<Room> createRoom({
    required String siteId,
    required String code,
    required int floor,
    required int rent,
    int paymentDueDays = defaultPaymentDueDays,
  });
  Future<Room> updateRoom(Room room);
  Future<Room> updateRoomDueDays(String roomId, int days);

  Future<List<Service>> listServices({String? siteId});
  Future<Service> createService({
    required String siteId,
    required String name,
    required int unitPrice,
    required ServiceUnit unit,
  });
  Future<Service> updateService(Service service);
  Future<List<RoomService>> listRoomServices(String roomId);
  Future<RoomService> attachService({
    required String roomId,
    required String serviceId,
    int quantity = 1,
  });
  Future<void> detachService(String roomServiceId);

  Future<List<Tenant>> listTenants();
  Future<Tenant?> getTenant(String id);
  Future<Tenant> createTenant({
    required String fullName,
    required String phone,
    required String citizenId,
  });

  Future<Contract?> activeContractForRoom(String roomId);
  Future<Contract> createContract({
    required String roomId,
    required String tenantId,
    required DateTime startDate,
    required int rent,
    int deposit = 0,
  });

  /// Thanh lý hợp đồng: cần ảnh kiểm tra và ảnh thanh lý. Phòng chuyển sang Hết hạn.
  Future<TerminationResult> terminateContract({
    required String roomId,
    required List<Uint8List> inspectionPhotos,
    required List<Uint8List> liquidationPhotos,
  });

  /// Sửa giá thuê và tiền cọc của hợp đồng đang hiệu lực. Giá thuê cũng là giá phòng.
  Future<Contract> updateContract(Contract contract);

  Future<List<Photo>> listRoomPhotos(String roomId);
  Future<Photo?> getPhoto(String id);

  Future<List<MeterReading>> listMeterReadings({String? roomId});
  Future<MeterReading> submitMeterReading({
    required String roomId,
    required String period,
    required MeterKind kind,
    required int startValue,
    required int endValue,
  });
  Future<MeterReading> confirmMeterReading(String id);

  Future<List<Invoice>> listInvoices({String? period, InvoiceStatus? status});
  Future<Invoice> getInvoice(String id);
  Future<Payment> recordPayment({
    required String invoiceId,
    required int amount,
    required String method,
    String? reference,
    required String idempotencyKey,
    Uint8List? proof,
  });

  Future<List<ActivityEntry>> listActivity();

  /// Lập hóa đơn nháp cho mọi phòng đang thuê có đủ chỉ số đã chốt trong kỳ.
  Future<InvoiceProposal> proposeInvoices({required String period});

  /// Doanh thu kỳ theo tiền đã thu, không tính khoản chuyển nợ sang hóa đơn thanh lý.
  Future<RevenueSummary> revenueForPeriod(String period);

  /// Chi phí, chỉ super admin dùng. Lọc theo kỳ nếu có.
  Future<List<Expense>> listExpenses({String? period});

  /// Thêm mới hoặc sửa khoản chi phí có cùng id.
  Future<void> saveExpense(Expense expense);

  Future<void> deleteExpense(String id);

  /// Đổi tiền phòng trên mọi hóa đơn chưa thu khoản nào cho khớp giá phòng hiện tại. Trả về số hóa đơn đã đổi.
  Future<int> syncUnpaidRents();
}

/// Repository đang dùng cho app: Firestore. Test dùng [MockRentalRepository].
final RentalRepository appRepository = FirestoreRentalRepository();

T? _firstWhereOrNull<T>(Iterable<T> items, bool Function(T) test) {
  for (final item in items) {
    if (test(item)) return item;
  }
  return null;
}

final _phoneRe = RegExp(r'^(0|\+84)(3|5|7|8|9)\d{8}$');
const _dueDaysMessage =
    'Hạn thanh toán từ $minPaymentDueDays đến $maxPaymentDueDays ngày';
final _citizenRe = RegExp(r'^\d{12}$');

class MockRentalRepository implements RentalRepository {
  MockRentalRepository({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final List<Site> _sites = List.of(sites);
  final List<Room> _rooms = List.of(rooms);
  final List<Tenant> _tenants = List.of(tenants);
  final List<Contract> _contracts = List.of(contracts);
  final List<MeterReading> _readings = List.of(readings);
  final List<Invoice> _invoices = List.of(invoices);
  final List<ActivityEntry> _activity = List.of(activity);
  final List<Expense> _expenses = [];
  final List<Service> _services = List.of(services);
  final List<RoomService> _roomServices = List.of(roomServices);
  final List<Photo> _photos = [];
  int _seq = 0;

  String _newId(String prefix) =>
      '$prefix-${_clock().microsecondsSinceEpoch}-${_seq++}';

  void _log(String action) => _activity.insert(
    0,
    ActivityEntry(time: _clock(), actor: 'Người dùng demo', action: action),
  );

  @override
  Future<List<Site>> listSites() async => List.unmodifiable(_sites);

  @override
  Future<Site> createSite({
    required String name,
    required String address,
    int electricRate = 0,
    int waterRate = 0,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) throw ArgumentError('Tên cơ sở không được trống');
    if (electricRate < 0 || waterRate < 0) {
      throw ArgumentError('Đơn giá không được âm');
    }
    final site = Site(
      id: _newId('s'),
      name: cleanName,
      address: address.trim(),
      electricRate: electricRate,
      waterRate: waterRate,
    );
    _sites.add(site);
    _log('Thêm cơ sở $cleanName');
    return site;
  }

  @override
  Future<List<Room>> listRooms({String? siteId, RoomStatus? status}) async => [
    for (final r in _rooms)
      if ((siteId == null || r.siteId == siteId) &&
          (status == null || r.status == status))
        r,
  ];

  @override
  Future<Room> getRoom(String id) async {
    final room = _firstWhereOrNull(_rooms, (r) => r.id == id);
    if (room == null) throw StateError('Không tìm thấy phòng $id');
    return room;
  }

  @override
  Future<Room> createRoom({
    required String siteId,
    required String code,
    required int floor,
    required int rent,
    int paymentDueDays = defaultPaymentDueDays,
  }) async {
    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty) throw ArgumentError('Mã phòng không được trống');
    if (rent <= 0) throw ArgumentError('Giá thuê phải lớn hơn 0');
    if (!isValidPaymentDueDays(paymentDueDays)) {
      throw ArgumentError(_dueDaysMessage);
    }
    if (_rooms.any((r) => r.siteId == siteId && r.code == normalized)) {
      throw DuplicateRoomCodeException(normalized);
    }
    final room = Room(
      id: _newId('r'),
      siteId: siteId,
      code: normalized,
      floor: floor,
      status: RoomStatus.vacant,
      rent: rent,
      paymentDueDays: paymentDueDays,
    );
    _rooms.add(room);
    _log('Thêm phòng $normalized');
    return room;
  }

  @override
  Future<Room> updateRoom(Room room) async {
    final index = _rooms.indexWhere((r) => r.id == room.id);
    if (index < 0) throw StateError('Không tìm thấy phòng ${room.id}');
    final code = room.code.trim().toUpperCase();
    if (code.isEmpty) throw ArgumentError('Mã phòng không được trống');
    if (room.rent <= 0) throw ArgumentError('Giá thuê phải lớn hơn 0');
    if (!isValidPaymentDueDays(room.paymentDueDays)) {
      throw ArgumentError(_dueDaysMessage);
    }
    if (_rooms.any(
      (r) => r.id != room.id && r.siteId == room.siteId && r.code == code,
    )) {
      throw DuplicateRoomCodeException(code);
    }
    _rooms[index] = Room(
      id: room.id,
      siteId: room.siteId,
      code: code,
      floor: room.floor,
      status: room.status,
      rent: room.rent,
      tenantName: room.tenantName,
      paymentDueDays: room.paymentDueDays,
    );
    // Giá thuê đổi thì hợp đồng đang hiệu lực đổi theo, như Firestore.
    final contract = await activeContractForRoom(room.id);
    if (contract != null && contract.rent != room.rent) {
      final ci = _contracts.indexOf(contract);
      _contracts[ci] = Contract(
        id: contract.id,
        roomId: contract.roomId,
        tenantId: contract.tenantId,
        startDate: contract.startDate,
        rent: room.rent,
        deposit: contract.deposit,
      );
      _repriceUnpaidRentMock(room.siteId, code, room.rent);
    }
    _log('Sửa phòng $code');
    return _rooms[index];
  }

  @override
  Future<Site> updateSite(Site site) async {
    final index = _sites.indexWhere((s) => s.id == site.id);
    if (index < 0) throw StateError('Không tìm thấy cơ sở ${site.id}');
    final cleanName = site.name.trim();
    if (cleanName.isEmpty) throw ArgumentError('Tên cơ sở không được trống');
    final updated = site.copyWith(
      name: cleanName,
      address: site.address.trim(),
    );
    _sites[index] = updated;
    _log('Sửa cơ sở $cleanName');
    return updated;
  }

  @override
  Future<Room> updateRoomDueDays(String roomId, int days) async {
    if (!isValidPaymentDueDays(days)) throw ArgumentError(_dueDaysMessage);
    final room = await getRoom(roomId);
    final updated = room.copyWith(paymentDueDays: days);
    await updateRoom(updated);
    _log('Đặt hạn thanh toán ${room.code} còn $days ngày');
    return updated;
  }

  @override
  Future<List<Service>> listServices({String? siteId}) async => [
    for (final s in _services)
      if (siteId == null || s.siteId == siteId) s,
  ];

  @override
  Future<Service> createService({
    required String siteId,
    required String name,
    required int unitPrice,
    required ServiceUnit unit,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) throw ArgumentError('Tên dịch vụ không được trống');
    if (unitPrice <= 0) throw ArgumentError('Đơn giá phải lớn hơn 0');
    final service = Service(
      id: _newId('sv'),
      siteId: siteId,
      name: cleanName,
      unitPrice: unitPrice,
      unit: unit,
      active: true,
    );
    _services.add(service);
    _log('Thêm dịch vụ $cleanName');
    return service;
  }

  @override
  Future<Service> updateService(Service service) async {
    final index = _services.indexWhere((s) => s.id == service.id);
    if (index < 0) throw StateError('Không tìm thấy dịch vụ ${service.id}');
    final cleanName = service.name.trim();
    if (cleanName.isEmpty) throw ArgumentError('Tên dịch vụ không được trống');
    if (service.unitPrice <= 0) throw ArgumentError('Đơn giá phải lớn hơn 0');
    final updated = service.copyWith(name: cleanName);
    _services[index] = updated;
    _log('Cập nhật dịch vụ $cleanName');
    return updated;
  }

  @override
  Future<List<RoomService>> listRoomServices(String roomId) async => [
    for (final rs in _roomServices)
      if (rs.roomId == roomId) rs,
  ];

  @override
  Future<RoomService> attachService({
    required String roomId,
    required String serviceId,
    int quantity = 1,
  }) async {
    final room = await getRoom(roomId);
    final service = _firstWhereOrNull(_services, (s) => s.id == serviceId);
    if (service == null) throw StateError('Không tìm thấy dịch vụ $serviceId');
    if (!service.active) {
      throw ArgumentError('Dịch vụ ${service.name} đang tắt');
    }
    if (_roomServices.any(
      (rs) => rs.roomId == roomId && rs.serviceId == serviceId,
    )) {
      throw const ServiceAlreadyAttachedException();
    }
    // Dịch vụ cố định tính một lần mỗi kỳ, số lượng luôn là 1.
    final effective = service.unit == ServiceUnit.fixed ? 1 : quantity;
    if (effective < 1) throw ArgumentError('Số lượng phải từ 1 trở lên');
    final roomService = RoomService(
      id: _newId('rs'),
      roomId: roomId,
      serviceId: serviceId,
      quantity: effective,
    );
    _roomServices.add(roomService);
    _log('Gắn ${service.name} vào phòng ${room.code}');
    return roomService;
  }

  @override
  Future<void> detachService(String roomServiceId) async {
    final index = _roomServices.indexWhere((rs) => rs.id == roomServiceId);
    if (index < 0) {
      throw StateError('Không tìm thấy dịch vụ gắn $roomServiceId');
    }
    final removed = _roomServices.removeAt(index);
    final service = _firstWhereOrNull(
      _services,
      (s) => s.id == removed.serviceId,
    );
    _log('Gỡ ${service?.name ?? removed.serviceId} khỏi phòng');
  }

  @override
  Future<List<Tenant>> listTenants() async => List.unmodifiable(_tenants);

  @override
  Future<Tenant?> getTenant(String id) async =>
      _firstWhereOrNull(_tenants, (t) => t.id == id);

  @override
  Future<Tenant> createTenant({
    required String fullName,
    required String phone,
    required String citizenId,
  }) async {
    final name = fullName.trim();
    final cleanPhone = phone.replaceAll(' ', '');
    if (name.isEmpty) throw ArgumentError('Họ tên không được trống');
    if (!_phoneRe.hasMatch(cleanPhone)) {
      throw ArgumentError('Số điện thoại không hợp lệ');
    }
    if (!_citizenRe.hasMatch(citizenId)) {
      throw ArgumentError('CCCD phải gồm 12 chữ số');
    }
    final tenant = Tenant(
      id: _newId('t'),
      fullName: name,
      phone: cleanPhone,
      citizenId: citizenId,
    );
    _tenants.add(tenant);
    _log('Thêm người thuê $name');
    return tenant;
  }

  @override
  Future<Contract?> activeContractForRoom(String roomId) async =>
      _firstWhereOrNull(_contracts, (c) => c.roomId == roomId && c.isActive);

  @override
  Future<Contract> createContract({
    required String roomId,
    required String tenantId,
    required DateTime startDate,
    required int rent,
    int deposit = 0,
  }) async {
    if (rent <= 0) throw ArgumentError('Giá thuê phải lớn hơn 0');
    if (deposit < 0) throw ArgumentError('Tiền cọc không được âm');
    final room = await getRoom(roomId);
    final tenant = await getTenant(tenantId);
    if (tenant == null) throw StateError('Không tìm thấy người thuê $tenantId');
    if (room.status != RoomStatus.vacant &&
        room.status != RoomStatus.reserved) {
      throw const RoomNotAvailableException();
    }
    if (await activeContractForRoom(roomId) != null) {
      throw const RoomNotAvailableException();
    }

    final contract = Contract(
      id: _newId('c'),
      roomId: roomId,
      tenantId: tenantId,
      startDate: startDate,
      rent: rent,
      deposit: deposit,
    );
    _contracts.add(contract);
    await updateRoom(
      room.copyWith(
        status: RoomStatus.occupied,
        tenantName: tenant.fullName,
        rent: rent,
      ),
    );
    _log('Ký hợp đồng phòng ${room.code} với ${tenant.fullName}');
    return contract;
  }

  @override
  Future<TerminationResult> terminateContract({
    required String roomId,
    required List<Uint8List> inspectionPhotos,
    required List<Uint8List> liquidationPhotos,
  }) async {
    if (inspectionPhotos.isEmpty || liquidationPhotos.isEmpty) {
      throw const TerminationNeedsPhotosException();
    }
    final room = await getRoom(roomId);
    final contract = await activeContractForRoom(roomId);
    if (contract == null) {
      throw StateError('Phòng ${room.code} không có hợp đồng đang hiệu lực');
    }
    final tenant = await getTenant(contract.tenantId);
    final now = _clock();

    final unpaid = [
      for (final inv in _invoices)
        if (inv.siteId == room.siteId &&
            inv.roomCode == room.code &&
            inv.remaining > 0)
          inv,
    ];
    final lines = settlementLines(unpaid: unpaid, deposit: contract.deposit);
    Invoice? settlement;
    if (lines.isNotEmpty) {
      settlement = Invoice(
        id: _newId('tl'),
        siteId: room.siteId,
        roomCode: room.code,
        tenant: tenant?.fullName ?? room.tenantName ?? '',
        period: 'Thanh lý',
        total: linesTotal(lines),
        dueDate: DateTime(now.year, now.month, now.day),
        lines: lines,
      );
      _invoices.add(settlement);
      // Nợ cũ được chuyển sang hóa đơn thanh lý để không thu trùng.
      for (final inv in unpaid) {
        final index = _invoices.indexOf(inv);
        _invoices[index] = inv.copyWith(
          payments: [
            ...inv.payments,
            Payment(
              id: _newId('p'),
              invoiceId: inv.id,
              amount: inv.remaining,
              method: Payment.settlementMethod,
              reference: settlement.id,
              paidAt: now,
              idempotencyKey: 'settle-${settlement.id}-${inv.id}',
            ),
          ],
        );
      }
    }

    final index = _contracts.indexOf(contract);
    final ended = contract.ended(now);
    _contracts[index] = ended;
    for (final bytes in inspectionPhotos) {
      _photos.add(_photo(room, ended.id, PhotoKind.inspection, bytes, now));
    }
    for (final bytes in liquidationPhotos) {
      _photos.add(_photo(room, ended.id, PhotoKind.liquidation, bytes, now));
    }
    await updateRoom(
      room.copyWith(status: RoomStatus.expired, clearTenant: true),
    );
    _log('Thanh lý hợp đồng phòng ${room.code}');
    return TerminationResult(contract: ended, settlement: settlement);
  }

  Photo _photo(
    Room room,
    String contractId,
    PhotoKind kind,
    Uint8List bytes,
    DateTime at,
  ) => Photo(
    id: _newId('ph'),
    siteId: room.siteId,
    kind: kind,
    data: base64Encode(bytes),
    createdAt: at,
    roomId: room.id,
    contractId: contractId,
  );

  @override
  Future<int> syncUnpaidRents() async {
    var count = 0;
    for (var i = 0; i < _invoices.length; i++) {
      final inv = _invoices[i];
      if (inv.payments.isNotEmpty) continue;
      final room = _firstWhereOrNull(
        _rooms,
        (r) => r.siteId == inv.siteId && r.code == inv.roomCode,
      );
      if (room == null) continue;
      final lines = repriceRent(inv.lines, room.rent);
      if (lines == null) continue;
      _invoices[i] = inv.copyWith(lines: lines, total: linesTotal(lines));
      count++;
    }
    return count;
  }

  /// Đổi tiền phòng của hóa đơn chưa thu khoản nào, như Firestore.
  void _repriceUnpaidRentMock(String siteId, String roomCode, int rent) {
    for (var i = 0; i < _invoices.length; i++) {
      final inv = _invoices[i];
      if (inv.siteId != siteId ||
          inv.roomCode != roomCode ||
          inv.payments.isNotEmpty) {
        continue;
      }
      final lines = repriceRent(inv.lines, rent);
      if (lines == null) continue;
      _invoices[i] = inv.copyWith(lines: lines, total: linesTotal(lines));
    }
  }

  @override
  Future<Contract> updateContract(Contract contract) async {
    if (contract.rent <= 0) throw ArgumentError('Giá thuê phải lớn hơn 0');
    if (contract.deposit < 0) throw ArgumentError('Tiền cọc không được âm');
    final index = _contracts.indexWhere((c) => c.id == contract.id);
    if (index < 0) throw StateError('Không tìm thấy hợp đồng ${contract.id}');
    final current = _contracts[index];
    if (!current.isActive) {
      throw StateError('Hợp đồng đã thanh lý, không sửa được');
    }
    final room = await getRoom(current.roomId);
    final updated = current.copyWith(
      rent: contract.rent,
      deposit: contract.deposit,
    );
    _contracts[index] = updated;
    if (updated.rent != current.rent) {
      _repriceUnpaidRentMock(room.siteId, room.code, updated.rent);
    }
    await updateRoom(room.copyWith(rent: updated.rent));
    return updated;
  }

  @override
  Future<List<Photo>> listRoomPhotos(String roomId) async => [
    for (final p in _photos)
      if (p.roomId == roomId) p,
  ];

  @override
  Future<Photo?> getPhoto(String id) async =>
      _firstWhereOrNull(_photos, (p) => p.id == id);

  @override
  Future<List<MeterReading>> listMeterReadings({String? roomId}) async => [
    for (final m in _readings)
      if (roomId == null || m.roomId == roomId) m,
  ];

  @override
  Future<MeterReading> submitMeterReading({
    required String roomId,
    required String period,
    required MeterKind kind,
    required int startValue,
    required int endValue,
  }) async {
    if (startValue < 0 || endValue < 0) {
      throw ArgumentError('Chỉ số không được âm');
    }
    if (endValue < startValue) {
      throw ArgumentError('Chỉ số cuối phải ≥ chỉ số đầu');
    }
    final existing = _firstWhereOrNull(
      _readings,
      (m) => m.roomId == roomId && m.period == period && m.kind == kind,
    );
    if (existing?.status == ReadingStatus.confirmed) {
      throw StateError('Kỳ này đã chốt, không sửa trực tiếp');
    }
    final reading = MeterReading(
      id: existing?.id ?? _newId('m'),
      roomId: roomId,
      period: period,
      kind: kind,
      startValue: startValue,
      endValue: endValue,
      status: ReadingStatus.draft,
    );
    if (existing != null) {
      _readings[_readings.indexOf(existing)] = reading;
    } else {
      _readings.add(reading);
    }
    return reading;
  }

  @override
  Future<MeterReading> confirmMeterReading(String id) async {
    final index = _readings.indexWhere((m) => m.id == id);
    if (index < 0) throw StateError('Không tìm thấy chỉ số $id');
    final current = _readings[index];
    if (current.status == ReadingStatus.confirmed) return current;
    final confirmed = current.copyWith(status: ReadingStatus.confirmed);
    _readings[index] = confirmed;
    _log('Chốt chỉ số ${current.kind.name} ${current.period}');
    return confirmed;
  }

  InvoiceStatus _status(Invoice i) => i.statusAt(_clock());

  @override
  Future<List<Invoice>> listInvoices({
    String? period,
    InvoiceStatus? status,
  }) async => [
    for (final i in _invoices)
      if ((period == null || i.period == period) &&
          (status == null || _status(i) == status))
        i,
  ];

  @override
  Future<Invoice> getInvoice(String id) async {
    final invoice = _firstWhereOrNull(_invoices, (i) => i.id == id);
    if (invoice == null) throw StateError('Không tìm thấy hóa đơn $id');
    return invoice;
  }

  @override
  Future<Payment> recordPayment({
    required String invoiceId,
    required int amount,
    required String method,
    String? reference,
    required String idempotencyKey,
    Uint8List? proof,
  }) async {
    final invoice = await getInvoice(invoiceId);
    // Idempotent: cùng khóa thì trả lại khoản đã ghi, không ghi trùng.
    final replay = _firstWhereOrNull(
      invoice.payments,
      (p) => p.idempotencyKey == idempotencyKey,
    );
    if (replay != null) return replay;

    if (amount <= 0) throw ArgumentError('Số tiền thu phải lớn hơn 0');
    if (method == 'transfer' &&
        (reference == null || reference.trim().isEmpty)) {
      throw ArgumentError('Chuyển khoản cần mã tham chiếu');
    }
    if (amount > invoice.remaining) {
      throw PaymentExceedsRemainingException(invoice.remaining);
    }

    String? proofId;
    if (proof != null) {
      proofId = _newId('ph');
      _photos.add(
        Photo(
          id: proofId,
          siteId: invoice.siteId,
          kind: PhotoKind.paymentProof,
          data: base64Encode(proof),
          createdAt: _clock(),
          invoiceId: invoiceId,
        ),
      );
    }
    final payment = Payment(
      id: _newId('p'),
      invoiceId: invoiceId,
      amount: amount,
      method: method,
      reference: (reference == null || reference.trim().isEmpty)
          ? null
          : reference.trim(),
      paidAt: _clock(),
      idempotencyKey: idempotencyKey,
      proofPhotoId: proofId,
    );
    final index = _invoices.indexOf(invoice);
    _invoices[index] = invoice.copyWith(
      payments: [...invoice.payments, payment],
    );
    _log('Thu $amount phòng ${invoice.roomCode} (${invoice.period})');
    return payment;
  }

  @override
  Future<List<ActivityEntry>> listActivity() async =>
      List.unmodifiable(_activity);

  @override
  Future<List<Expense>> listExpenses({String? period}) async => [
    for (final e in _expenses)
      if (period == null || periodOf(e.date) == period) e,
  ];

  @override
  Future<void> saveExpense(Expense expense) async {
    if (expense.amount <= 0) throw ArgumentError('Số tiền phải lớn hơn 0');
    final index = _expenses.indexWhere((e) => e.id == expense.id);
    if (index < 0) {
      _expenses.add(expense);
    } else {
      _expenses[index] = expense;
    }
  }

  @override
  Future<void> deleteExpense(String id) async =>
      _expenses.removeWhere((e) => e.id == id);

  @override
  Future<RevenueSummary> revenueForPeriod(String period) async =>
      revenueOf(await listInvoices(), period);

  @override
  Future<InvoiceProposal> proposeInvoices({required String period}) async {
    final ym = parsePeriod(period);
    var created = 0;
    final skipped = <String>[];
    for (final room in _rooms.where((r) => r.status == RoomStatus.occupied)) {
      final site = _firstWhereOrNull(_sites, (s) => s.id == room.siteId);
      if (site == null) continue;
      if (_invoices.any(
        (i) =>
            i.period == period &&
            i.siteId == room.siteId &&
            i.roomCode == room.code,
      )) {
        skipped.add('${room.code}: đã có hóa đơn kỳ này');
        continue;
      }
      final contract = _firstWhereOrNull(
        _contracts,
        (c) => c.roomId == room.id,
      );
      if (contract == null) {
        skipped.add('${room.code}: không có hợp đồng');
        continue;
      }
      MeterReading? confirmed(MeterKind kind) => _firstWhereOrNull(
        _readings,
        (m) =>
            m.roomId == room.id &&
            m.period == period &&
            m.kind == kind &&
            m.status == ReadingStatus.confirmed,
      );
      final charges = <ServiceCharge>[
        for (final rs in _roomServices.where((rs) => rs.roomId == room.id))
          if (_firstWhereOrNull(_services, (s) => s.id == rs.serviceId)
              case final service?)
            (
              name: service.name,
              unit: service.unit,
              unitPrice: service.unitPrice,
              quantity: rs.quantity,
            ),
      ];
      final draft = buildRoomBill(
        rent: room.rent, // Giá phòng hiện tại, không lấy giá lúc ký hợp đồng.
        site: site,
        electric: confirmed(MeterKind.electric),
        water: confirmed(MeterKind.water),
        services: charges,
      );
      if (draft.problem != null) {
        skipped.add('${room.code}: ${draft.problem}');
        continue;
      }
      final tenant = _firstWhereOrNull(
        _tenants,
        (t) => t.id == contract.tenantId,
      );
      _invoices.add(
        Invoice(
          id: _newId('inv'),
          siteId: room.siteId,
          roomCode: room.code,
          tenant: tenant?.fullName ?? '',
          period: period,
          total: draft.total,
          dueDate: dueDateFor(ym.year, ym.month, room.paymentDueDays),
          lines: draft.lines,
        ),
      );
      created++;
    }
    if (created > 0) _log('Đề xuất $created hóa đơn $period');
    return InvoiceProposal(created: created, skipped: skipped);
  }
}
