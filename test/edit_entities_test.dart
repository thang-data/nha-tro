import 'package:flutter_test/flutter_test.dart';
import 'package:rental_manager/data/models.dart';
import 'package:rental_manager/data/repository.dart';

void main() {
  test('admin sửa tên và địa chỉ cơ sở', () async {
    final repo = MockRentalRepository();
    final site = (await repo.listSites()).first;
    final updated = await repo.updateSite(
      Site(id: site.id, name: '  Cơ sở mới ', address: ' 1 Đường A '),
    );
    expect(updated.name, 'Cơ sở mới');
    expect(updated.address, '1 Đường A');
    expect((await repo.listSites()).first.name, 'Cơ sở mới');
  });

  test('sửa phòng không được trùng mã trong cùng cơ sở', () async {
    final repo = MockRentalRepository();
    final rooms = await repo.listRooms(siteId: 's1');
    expect(rooms.length, greaterThanOrEqualTo(2));
    final first = rooms[0];
    final second = rooms[1];
    expect(
      () => repo.updateRoom(
        Room(
          id: second.id,
          siteId: second.siteId,
          code: first.code,
          floor: second.floor,
          status: second.status,
          rent: second.rent,
          paymentDueDays: second.paymentDueDays,
        ),
      ),
      throwsA(isA<DuplicateRoomCodeException>()),
    );
  });

  test('sửa phòng: đổi tầng và giá thuê được lưu', () async {
    final repo = MockRentalRepository();
    final room = (await repo.listRooms(siteId: 's1')).first;
    await repo.updateRoom(
      Room(
        id: room.id,
        siteId: room.siteId,
        code: room.code,
        floor: 5,
        status: room.status,
        rent: 4500000,
        paymentDueDays: room.paymentDueDays,
      ),
    );
    final after = await repo.getRoom(room.id);
    expect(after.floor, 5);
    expect(after.rent, 4500000);
  });
}
