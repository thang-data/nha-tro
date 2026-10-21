import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../auth/access.dart';
import '../core/image_compress.dart';
import '../core/validators.dart';
import 'billing.dart';
import 'models.dart';
import 'repository.dart';

final _phoneRe = RegExp(r'^(0|\+84)(3|5|7|8|9)\d{8}$');
final _citizenRe = RegExp(r'^\d{12}$');
const _dueDaysMessage =
    'Hạn thanh toán từ $minPaymentDueDays đến $maxPaymentDueDays ngày';

T? _firstOrNull<T>(Iterable<T> items, bool Function(T) test) {
  for (final item in items) {
    if (test(item)) return item;
  }
  return null;
}

/// Lưu dữ liệu trên Cloud Firestore. Mỗi collection là một bảng; field dùng
/// đúng key JSON của models.dart. Quyền truy cập do Firestore rules quyết định.
class FirestoreRentalRepository implements RentalRepository {
  FirestoreRentalRepository({FirebaseFirestore? db, DateTime Function()? clock})
    : _db = db ?? FirebaseFirestore.instance,
      _clock = clock ?? DateTime.now;

  final FirebaseFirestore _db;
  final DateTime Function() _clock;

  CollectionReference<Map<String, dynamic>> _col(String name) =>
      _db.collection(name);

  Map<String, dynamic> _withId(DocumentSnapshot<Map<String, dynamic>> doc) => {
    ...?doc.data(),
    'id': doc.id,
  };

  Future<List<Map<String, dynamic>>> _all(
    Query<Map<String, dynamic>> query,
  ) async {
    final snap = await query.get();
    return [for (final d in snap.docs) _withId(d)];
  }

  Future<void> _log(String action) => _col('activity').add({
    'time': _clock().toIso8601String(),
    'actor': FirebaseAuth.instance.currentUser?.email ?? 'Người dùng',
    'action': action,
  });

  InvoiceStatus _status(Invoice i) => i.statusAt(_clock());

  /// Cơ sở nhân viên được xem. Null nghĩa là không giới hạn (admin).
  List<String>? get _scopeSites {
    final access = currentAccess;
    if (access == null || access.hasFullAccess) return null;
    return access.siteIds.toList();
  }

  /// Thêm điều kiện cơ sở cho truy vấn. Trả null nếu nhân viên không có cơ sở nào.
  Query<Map<String, dynamic>>? _scopedQuery(
    Query<Map<String, dynamic>> query,
    String field,
    String? siteId,
  ) {
    final scope = _scopeSites;
    if (scope == null) {
      return siteId == null ? query : query.where(field, isEqualTo: siteId);
    }
    if (siteId != null) {
      if (!scope.contains(siteId)) return null;
      return query.where(field, isEqualTo: siteId);
    }
    if (scope.isEmpty) return null;
    return query.where(field, whereIn: scope);
  }

  // ---- Cơ sở & phòng ----

  @override
  Future<List<Site>> listSites() async {
    Query<Map<String, dynamic>> query = _col('sites');
    final scope = _scopeSites;
    if (scope != null) {
      if (scope.isEmpty) return [];
      query = query.where(FieldPath.documentId, whereIn: scope);
    }
    return [for (final j in await _all(query)) Site.fromJson(j)];
  }

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
    final ref = _col('sites').doc();
    final site = Site(
      id: ref.id,
      name: cleanName,
      address: address.trim(),
      electricRate: electricRate,
      waterRate: waterRate,
    );
    await ref.set(site.toJson());
    await _log('Thêm cơ sở $cleanName');
    return site;
  }

  @override
  Future<List<Room>> listRooms({String? siteId, RoomStatus? status}) async {
    Query<Map<String, dynamic>> query = _col('rooms');
    final scoped = _scopedQuery(query, 'site_id', siteId);
    if (scoped == null) return [];
    query = scoped;
    if (status != null) query = query.where('status', isEqualTo: status.name);
    final rooms = [for (final j in await _all(query)) Room.fromJson(j)];
    rooms.sort((a, b) => a.code.compareTo(b.code));
    return rooms;
  }

  @override
  Future<Room> getRoom(String id) async {
    final doc = await _col('rooms').doc(id).get();
    if (!doc.exists) throw StateError('Không tìm thấy phòng $id');
    return Room.fromJson(_withId(doc));
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
    final dup = await _col('rooms')
        .where('site_id', isEqualTo: siteId)
        .where('room_code', isEqualTo: normalized)
        .limit(1)
        .get();
    if (dup.docs.isNotEmpty) throw DuplicateRoomCodeException(normalized);

    final ref = _col('rooms').doc();
    final room = Room(
      id: ref.id,
      siteId: siteId,
      code: normalized,
      floor: floor,
      status: RoomStatus.vacant,
      rent: rent,
      paymentDueDays: paymentDueDays,
    );
    await ref.set(room.toJson());
    await _log('Thêm phòng $normalized');
    return room;
  }

  @override
  Future<Room> updateRoom(Room room) async {
    final ref = _col('rooms').doc(room.id);
    if (!(await ref.get()).exists) {
      throw StateError('Không tìm thấy phòng ${room.id}');
    }
    final code = room.code.trim().toUpperCase();
    if (code.isEmpty) throw ArgumentError('Mã phòng không được trống');
    if (room.rent <= 0) throw ArgumentError('Giá thuê phải lớn hơn 0');
    if (!isValidPaymentDueDays(room.paymentDueDays)) {
      throw ArgumentError(_dueDaysMessage);
    }
    final dup = await _col('rooms')
        .where('site_id', isEqualTo: room.siteId)
        .where('room_code', isEqualTo: code)
        .get();
    if (dup.docs.any((d) => d.id != room.id)) {
      throw DuplicateRoomCodeException(code);
    }
    final updated = Room(
      id: room.id,
      siteId: room.siteId,
      code: code,
      floor: room.floor,
      status: room.status,
      rent: room.rent,
      tenantName: room.tenantName,
      paymentDueDays: room.paymentDueDays,
    );
    // Giá thuê đổi thì hợp đồng đang hiệu lực đổi theo, để hóa đơn mới dùng đúng giá.
    final contract = await activeContractForRoom(room.id);
    final batch = _db.batch()..set(ref, updated.toJson());
    if (contract != null && contract.rent != updated.rent) {
      batch.update(_col('contracts').doc(contract.id), {'rent': updated.rent});
      await _repriceUnpaidRent(batch, room.siteId, code, updated.rent);
    }
    await batch.commit();
    await _log('Sửa phòng $code');
    return updated;
  }

  @override
  Future<Site> updateSite(Site site) async {
    final cleanName = site.name.trim();
    if (cleanName.isEmpty) throw ArgumentError('Tên cơ sở không được trống');
    final ref = _col('sites').doc(site.id);
    if (!(await ref.get()).exists) {
      throw StateError('Không tìm thấy cơ sở ${site.id}');
    }
    final updated = site.copyWith(
      name: cleanName,
      address: site.address.trim(),
    );
    await ref.set(updated.toJson());
    await _log('Sửa cơ sở $cleanName');
    return updated;
  }

  @override
  Future<Room> updateRoomDueDays(String roomId, int days) async {
    if (!isValidPaymentDueDays(days)) throw ArgumentError(_dueDaysMessage);
    final room = await getRoom(roomId);
    final updated = room.copyWith(paymentDueDays: days);
    await updateRoom(updated);
    await _log('Đặt hạn thanh toán ${room.code} còn $days ngày');
    return updated;
  }

  // ---- Dịch vụ ----

  @override
  Future<List<Service>> listServices({String? siteId}) async {
    final scoped = _scopedQuery(_col('services'), 'site_id', siteId);
    if (scoped == null) return [];
    final query = scoped;
    return [for (final j in await _all(query)) Service.fromJson(j)];
  }

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
    final ref = _col('services').doc();
    final service = Service(
      id: ref.id,
      siteId: siteId,
      name: cleanName,
      unitPrice: unitPrice,
      unit: unit,
      active: true,
    );
    await ref.set(service.toJson());
    await _log('Thêm dịch vụ $cleanName');
    return service;
  }

  @override
  Future<Service> updateService(Service service) async {
    final cleanName = service.name.trim();
    if (cleanName.isEmpty) throw ArgumentError('Tên dịch vụ không được trống');
    if (service.unitPrice <= 0) throw ArgumentError('Đơn giá phải lớn hơn 0');
    final ref = _col('services').doc(service.id);
    if (!(await ref.get()).exists) {
      throw StateError('Không tìm thấy dịch vụ ${service.id}');
    }
    final updated = service.copyWith(name: cleanName);
    await ref.set(updated.toJson());
    await _log('Cập nhật dịch vụ $cleanName');
    return updated;
  }

  @override
  Future<List<RoomService>> listRoomServices(String roomId) async => [
    for (final j in await _all(
      _col('room_services').where('room_id', isEqualTo: roomId),
    ))
      RoomService.fromJson(j),
  ];

  @override
  Future<RoomService> attachService({
    required String roomId,
    required String serviceId,
    int quantity = 1,
  }) async {
    final room = await getRoom(roomId);
    final serviceDoc = await _col('services').doc(serviceId).get();
    if (!serviceDoc.exists) {
      throw StateError('Không tìm thấy dịch vụ $serviceId');
    }
    final service = Service.fromJson(_withId(serviceDoc));
    if (!service.active) {
      throw ArgumentError('Dịch vụ ${service.name} đang tắt');
    }
    final dup = await _col('room_services')
        .where('room_id', isEqualTo: roomId)
        .where('service_id', isEqualTo: serviceId)
        .limit(1)
        .get();
    if (dup.docs.isNotEmpty) throw const ServiceAlreadyAttachedException();

    // Dịch vụ cố định tính một lần mỗi kỳ, số lượng luôn là 1.
    final effective = service.unit == ServiceUnit.fixed ? 1 : quantity;
    if (effective < 1) throw ArgumentError('Số lượng phải từ 1 trở lên');
    final ref = _col('room_services').doc();
    final roomService = RoomService(
      id: ref.id,
      roomId: roomId,
      serviceId: serviceId,
      quantity: effective,
    );
    await ref.set(roomService.toJson());
    await _log('Gắn ${service.name} vào phòng ${room.code}');
    return roomService;
  }

  @override
  Future<void> detachService(String roomServiceId) async {
    final ref = _col('room_services').doc(roomServiceId);
    final doc = await ref.get();
    if (!doc.exists) {
      throw StateError('Không tìm thấy dịch vụ gắn $roomServiceId');
    }
    final removed = RoomService.fromJson(_withId(doc));
    final serviceDoc = await _col('services').doc(removed.serviceId).get();
    await ref.delete();
    final name = serviceDoc.exists
        ? Service.fromJson(_withId(serviceDoc)).name
        : removed.serviceId;
    await _log('Gỡ $name khỏi phòng');
  }

  // ---- Người thuê & hợp đồng ----

  @override
  Future<List<Tenant>> listTenants() async => [
    for (final j in await _all(_col('tenants'))) Tenant.fromJson(j),
  ];

  @override
  Future<Tenant?> getTenant(String id) async {
    final doc = await _col('tenants').doc(id).get();
    return doc.exists ? Tenant.fromJson(_withId(doc)) : null;
  }

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
    final ref = _col('tenants').doc();
    final tenant = Tenant(
      id: ref.id,
      fullName: name,
      phone: cleanPhone,
      citizenId: citizenId,
    );
    await ref.set(tenant.toJson());
    await _log('Thêm người thuê $name');
    return tenant;
  }

  @override
  Future<Contract?> activeContractForRoom(String roomId) async {
    final snap = await _col('contracts')
        .where('room_id', isEqualTo: roomId)
        .where('status', isEqualTo: 'active')
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return Contract.fromJson(_withId(snap.docs.first));
  }

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

    final ref = _col('contracts').doc();
    final contract = Contract(
      id: ref.id,
      roomId: roomId,
      tenantId: tenantId,
      startDate: startDate,
      rent: rent,
      deposit: deposit,
    );
    final batch = _db.batch()
      ..set(ref, contract.toJson())
      ..update(
        _col('rooms').doc(roomId),
        room
            .copyWith(
              status: RoomStatus.occupied,
              tenantName: tenant.fullName,
              rent: rent,
            )
            .toJson(),
      );
    await batch.commit();
    await _log('Ký hợp đồng phòng ${room.code} với ${tenant.fullName}');
    return contract;
  }

  /// Thanh lý trong một batch: hóa đơn thanh lý, chuyển nợ cũ, kết thúc hợp đồng,
  /// phòng sang Hết hạn, lưu ảnh và ghi nhật ký. Hoặc tất cả thành công, hoặc không có gì.
  @override
  Future<TerminationResult> terminateContract({
    required String roomId,
    required List<Uint8List> inspectionPhotos,
    required List<Uint8List> liquidationPhotos,
  }) async {
    if (inspectionPhotos.isEmpty || liquidationPhotos.isEmpty) {
      throw const TerminationNeedsPhotosException();
    }
    if (inspectionPhotos.length > maxPhotosPerKind ||
        liquidationPhotos.length > maxPhotosPerKind) {
      throw ArgumentError('Mỗi loại ảnh tối đa $maxPhotosPerKind ảnh');
    }
    final room = await getRoom(roomId);
    final contract = await activeContractForRoom(roomId);
    if (contract == null) {
      throw StateError('Phòng ${room.code} không có hợp đồng đang hiệu lực');
    }
    final tenant = await getTenant(contract.tenantId);
    final now = _clock();

    final invoiceQuery = _scopedQuery(
      _col('invoices').where('room_code', isEqualTo: room.code),
      'site_id',
      room.siteId,
    );
    final unpaid = <Invoice>[];
    if (invoiceQuery != null) {
      for (final j in await _all(invoiceQuery)) {
        final invoice = Invoice.fromJson(j);
        if (invoice.remaining > 0) unpaid.add(invoice);
      }
    }

    final batch = _db.batch();
    final lines = settlementLines(unpaid: unpaid, deposit: contract.deposit);
    Invoice? settlement;
    if (lines.isNotEmpty) {
      final ref = _col('invoices').doc();
      settlement = Invoice(
        id: ref.id,
        siteId: room.siteId,
        roomCode: room.code,
        tenant: tenant?.fullName ?? room.tenantName ?? '',
        period: 'Thanh lý',
        total: linesTotal(lines),
        dueDate: DateTime(now.year, now.month, now.day),
        lines: lines,
      );
      batch.set(ref, settlement.toJson());
      // Nợ cũ được chuyển sang hóa đơn thanh lý để không thu trùng.
      for (final inv in unpaid) {
        final carried = Payment(
          id: _db.collection('invoices').doc().id,
          invoiceId: inv.id,
          amount: inv.remaining,
          method: Payment.settlementMethod,
          reference: ref.id,
          paidAt: now,
          idempotencyKey: 'settle-${ref.id}-${inv.id}',
        );
        batch.update(_col('invoices').doc(inv.id), {
          'payments': [
            for (final p in [...inv.payments, carried]) p.toJson(),
          ],
        });
      }
    }

    final ended = contract.ended(now);
    batch.update(_col('contracts').doc(contract.id), {
      'status': 'ended',
      'ended_at': now.toIso8601String(),
    });
    batch.update(
      _col('rooms').doc(room.id),
      room.copyWith(status: RoomStatus.expired, clearTenant: true).toJson(),
    );
    for (final (kind, photos) in [
      (PhotoKind.inspection, inspectionPhotos),
      (PhotoKind.liquidation, liquidationPhotos),
    ]) {
      for (final bytes in photos) {
        _checkPhotoSize(bytes);
        final ref = _col('photos').doc();
        batch.set(
          ref,
          Photo(
            id: ref.id,
            siteId: room.siteId,
            kind: kind,
            data: base64Encode(bytes),
            createdAt: now,
            roomId: room.id,
            contractId: contract.id,
          ).toJson(),
        );
      }
    }
    batch.set(_col('activity').doc(), {
      'time': now.toIso8601String(),
      'actor': FirebaseAuth.instance.currentUser?.email ?? 'Người dùng',
      'action': 'Thanh lý hợp đồng phòng ${room.code}',
    });
    await batch.commit();
    return TerminationResult(contract: ended, settlement: settlement);
  }

  void _checkPhotoSize(Uint8List bytes) {
    if (bytes.length > maxPhotoBytes) {
      throw ArgumentError('Ảnh quá lớn sau khi nén, vui lòng chọn ảnh khác');
    }
  }

  @override
  Future<List<Photo>> listRoomPhotos(String roomId) async {
    final room = await getRoom(roomId);
    final query = _scopedQuery(
      _col('photos').where('room_id', isEqualTo: roomId),
      'site_id',
      room.siteId,
    );
    if (query == null) return [];
    final photos = [for (final j in await _all(query)) Photo.fromJson(j)];
    photos.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return photos;
  }

  @override
  Future<Photo?> getPhoto(String id) async {
    final doc = await _col('photos').doc(id).get();
    if (!doc.exists) return null;
    return Photo.fromJson(_withId(doc));
  }

  @override
  Future<int> syncUnpaidRents() async {
    final rooms = {
      for (final r in await listRooms()) '${r.siteId}|${r.code}': r,
    };
    final batch = _db.batch();
    var count = 0;
    for (final invoice in await listInvoices()) {
      if (invoice.payments.isNotEmpty) continue;
      final room = rooms['${invoice.siteId}|${invoice.roomCode}'];
      if (room == null) continue;
      final lines = repriceRent(invoice.lines, room.rent);
      if (lines == null) continue;
      final updated = invoice.copyWith(lines: lines, total: linesTotal(lines));
      batch.set(_col('invoices').doc(invoice.id), updated.toJson());
      count++;
    }
    if (count > 0) await batch.commit();
    return count;
  }

  /// Đổi tiền phòng của hóa đơn chưa thu khoản nào. Hóa đơn đã thu giữ nguyên.
  Future<void> _repriceUnpaidRent(
    WriteBatch batch,
    String siteId,
    String roomCode,
    int rent,
  ) async {
    final query = _scopedQuery(
      _col('invoices').where('room_code', isEqualTo: roomCode),
      'site_id',
      siteId,
    );
    if (query == null) return;
    for (final j in await _all(query)) {
      final invoice = Invoice.fromJson(j);
      if (invoice.payments.isNotEmpty) continue;
      final lines = repriceRent(invoice.lines, rent);
      if (lines == null) continue;
      final updated = invoice.copyWith(lines: lines, total: linesTotal(lines));
      batch.set(_col('invoices').doc(invoice.id), updated.toJson());
    }
  }

  @override
  Future<Contract> updateContract(Contract contract) async {
    if (contract.rent <= 0) throw ArgumentError('Giá thuê phải lớn hơn 0');
    if (contract.deposit < 0) throw ArgumentError('Tiền cọc không được âm');
    final snap = await _col('contracts').doc(contract.id).get();
    if (!snap.exists) {
      throw StateError('Không tìm thấy hợp đồng ${contract.id}');
    }
    final current = Contract.fromJson(_withId(snap));
    if (!current.isActive) {
      throw StateError('Hợp đồng đã thanh lý, không sửa được');
    }
    final room = await getRoom(current.roomId);
    final updated = current.copyWith(
      rent: contract.rent,
      deposit: contract.deposit,
    );
    final batch = _db.batch()
      ..update(_col('contracts').doc(current.id), {
        'rent': updated.rent,
        'deposit': updated.deposit,
      })
      ..update(_col('rooms').doc(room.id), {'rent': updated.rent});
    if (updated.rent != current.rent) {
      await _repriceUnpaidRent(batch, room.siteId, room.code, updated.rent);
    }
    await batch.commit();
    await _log('Sửa hợp đồng phòng ${room.code}');
    return updated;
  }

  // ---- Chỉ số điện nước ----

  @override
  Future<List<MeterReading>> listMeterReadings({String? roomId}) async {
    if (roomId != null) {
      final query = _col('meter_readings').where('room_id', isEqualTo: roomId);
      return [for (final j in await _all(query)) MeterReading.fromJson(j)];
    }
    // Nhân viên: chỉ lấy chỉ số của phòng thuộc cơ sở được gán.
    final scope = _scopeSites;
    if (scope == null) {
      return [
        for (final j in await _all(_col('meter_readings')))
          MeterReading.fromJson(j),
      ];
    }
    final roomIds = [for (final r in await listRooms()) r.id];
    final result = <MeterReading>[];
    for (var i = 0; i < roomIds.length; i += 30) {
      final chunk = roomIds.sublist(i, min(i + 30, roomIds.length));
      final query = _col('meter_readings').where('room_id', whereIn: chunk);
      result.addAll([
        for (final j in await _all(query)) MeterReading.fromJson(j),
      ]);
    }
    return result;
  }

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
    // Mỗi (phòng, kỳ, loại) chỉ có một chỉ số. Tìm bằng truy vấn, không dùng
    // kỳ làm id vì kỳ dạng "Tháng 10/2026" chứa "/" (id Firestore không cho phép).
    final found = await _col('meter_readings')
        .where('room_id', isEqualTo: roomId)
        .where('period', isEqualTo: period)
        .where('kind', isEqualTo: kind.name)
        .limit(1)
        .get();
    final ref = found.docs.isEmpty
        ? _col('meter_readings').doc()
        : found.docs.first.reference;
    if (found.docs.isNotEmpty &&
        MeterReading.fromJson(_withId(found.docs.first)).status ==
            ReadingStatus.confirmed) {
      throw StateError('Kỳ này đã chốt, không sửa trực tiếp');
    }
    final reading = MeterReading(
      id: ref.id,
      roomId: roomId,
      period: period,
      kind: kind,
      startValue: startValue,
      endValue: endValue,
      status: ReadingStatus.draft,
    );
    await ref.set(reading.toJson());
    return reading;
  }

  @override
  Future<MeterReading> confirmMeterReading(String id) async {
    final ref = _col('meter_readings').doc(id);
    final doc = await ref.get();
    if (!doc.exists) throw StateError('Không tìm thấy chỉ số $id');
    final current = MeterReading.fromJson(_withId(doc));
    if (current.status == ReadingStatus.confirmed) return current;
    final confirmed = current.copyWith(status: ReadingStatus.confirmed);
    await ref.update({'status': ReadingStatus.confirmed.name});
    await _log('Chốt chỉ số ${current.kind.name} ${current.period}');
    return confirmed;
  }

  // ---- Hóa đơn & thu tiền ----

  @override
  Future<List<Invoice>> listInvoices({
    String? period,
    InvoiceStatus? status,
  }) async {
    Query<Map<String, dynamic>> query = _col('invoices');
    if (period != null) query = query.where('period', isEqualTo: period);
    final scoped = _scopedQuery(query, 'site_id', null);
    if (scoped == null) return [];
    query = scoped;
    return [
      for (final j in await _all(query))
        if (status == null || _status(Invoice.fromJson(j)) == status)
          Invoice.fromJson(j),
    ];
  }

  @override
  Future<Invoice> getInvoice(String id) async {
    final doc = await _col('invoices').doc(id).get();
    if (!doc.exists) throw StateError('Không tìm thấy hóa đơn $id');
    return Invoice.fromJson(_withId(doc));
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
    final ref = _col('invoices').doc(invoiceId);
    final cleanRef = (reference == null || reference.trim().isEmpty)
        ? null
        : reference.trim();
    final paidAt = _clock();
    if (proof != null) _checkPhotoSize(proof);
    final proofRef = proof == null ? null : _col('photos').doc();

    final payment = await _db.runTransaction<Payment>((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw StateError('Không tìm thấy hóa đơn $invoiceId');
      final invoice = Invoice.fromJson(_withId(snap));

      // Idempotent: cùng khóa thì trả lại khoản đã ghi, không ghi trùng.
      final replay = _firstOrNull(
        invoice.payments,
        (p) => p.idempotencyKey == idempotencyKey,
      );
      if (replay != null) return replay;

      if (amount <= 0) throw ArgumentError('Số tiền thu phải lớn hơn 0');
      if (method == 'transfer' && cleanRef == null) {
        throw ArgumentError('Chuyển khoản cần mã tham chiếu');
      }
      if (amount > invoice.remaining) {
        throw PaymentExceedsRemainingException(invoice.remaining);
      }

      final created = Payment(
        id: _db.collection('invoices').doc().id,
        invoiceId: invoiceId,
        amount: amount,
        method: method,
        reference: cleanRef,
        paidAt: paidAt,
        idempotencyKey: idempotencyKey,
        proofPhotoId: proofRef?.id,
      );
      if (proofRef != null && proof != null) {
        tx.set(
          proofRef,
          Photo(
            id: proofRef.id,
            siteId: invoice.siteId,
            kind: PhotoKind.paymentProof,
            data: base64Encode(proof),
            createdAt: paidAt,
            invoiceId: invoiceId,
          ).toJson(),
        );
      }
      tx.update(ref, {
        'payments': [
          for (final p in [...invoice.payments, created]) p.toJson(),
        ],
      });
      tx.set(_col('activity').doc(), {
        'time': paidAt.toIso8601String(),
        'actor': FirebaseAuth.instance.currentUser?.email ?? 'Người dùng',
        'action': 'Thu $amount phòng ${invoice.roomCode} (${invoice.period})',
      });
      return created;
    });
    return payment;
  }

  // ---- Nhật ký ----

  @override
  Future<List<Expense>> listExpenses({String? period}) async {
    final all = [
      for (final j in await _all(_col('expenses'))) Expense.fromJson(j),
    ];
    return [
      for (final e in all)
        if (period == null || periodOf(e.date) == period) e,
    ];
  }

  @override
  Future<void> saveExpense(Expense expense) async {
    if (expense.amount <= 0) throw ArgumentError('Số tiền phải lớn hơn 0');
    await _col('expenses').doc(expense.id).set(expense.toJson());
  }

  @override
  Future<void> deleteExpense(String id) => _col('expenses').doc(id).delete();

  @override
  Future<RevenueSummary> revenueForPeriod(String period) async =>
      revenueOf(await listInvoices(), period);

  @override
  Future<InvoiceProposal> proposeInvoices({required String period}) async {
    final ym = parsePeriod(period);
    final sites = {for (final s in await listSites()) s.id: s};
    final services = {for (final s in await listServices()) s.id: s};
    final rooms = await listRooms(status: RoomStatus.occupied);
    final readings = await listMeterReadings();
    final existing = await listInvoices(period: period);

    final batch = _db.batch();
    var created = 0;
    final skipped = <String>[];
    for (final room in rooms) {
      final site = sites[room.siteId];
      if (site == null) continue;
      if (existing.any(
        (i) => i.siteId == room.siteId && i.roomCode == room.code,
      )) {
        skipped.add('${room.code}: đã có hóa đơn kỳ này');
        continue;
      }
      final contract = await activeContractForRoom(room.id);
      if (contract == null) {
        skipped.add('${room.code}: không có hợp đồng');
        continue;
      }
      MeterReading? confirmed(MeterKind kind) => _firstOrNull(
        readings,
        (m) =>
            m.roomId == room.id &&
            m.period == period &&
            m.kind == kind &&
            m.status == ReadingStatus.confirmed,
      );
      final charges = <ServiceCharge>[];
      for (final rs in await listRoomServices(room.id)) {
        final service = services[rs.serviceId];
        if (service == null) continue;
        charges.add((
          name: service.name,
          unit: service.unit,
          unitPrice: service.unitPrice,
          quantity: rs.quantity,
        ));
      }
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
      final tenant = await getTenant(contract.tenantId);
      final ref = _col('invoices').doc();
      final invoice = Invoice(
        id: ref.id,
        siteId: room.siteId,
        roomCode: room.code,
        tenant: tenant?.fullName ?? '',
        period: period,
        total: draft.total,
        dueDate: dueDateFor(ym.year, ym.month, room.paymentDueDays),
        lines: draft.lines,
      );
      batch.set(ref, invoice.toJson());
      created++;
    }
    if (created > 0) {
      batch.set(_col('activity').doc(), {
        'time': _clock().toIso8601String(),
        'actor': currentAccess?.email ?? 'Người dùng',
        'action': 'Đề xuất $created hóa đơn $period',
      });
      await batch.commit();
    }
    return InvoiceProposal(created: created, skipped: skipped);
  }

  @override
  Future<List<ActivityEntry>> listActivity() async {
    final snap = await _col('activity')
        .orderBy('time', descending: true)
        .limit(200)
        .get();
    return [for (final d in snap.docs) ActivityEntry.fromJson(d.data())];
  }
}
