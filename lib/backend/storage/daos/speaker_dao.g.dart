// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'speaker_dao.dart';

// ignore_for_file: type=lint
mixin _$SpeakerDaoMixin on DatabaseAccessor<AppDatabase> {
  $MeetingsTable get meetings => attachedDatabase.meetings;
  $SpeakersTable get speakers => attachedDatabase.speakers;
  SpeakerDaoManager get managers => SpeakerDaoManager(this);
}

class SpeakerDaoManager {
  final _$SpeakerDaoMixin _db;
  SpeakerDaoManager(this._db);
  $$MeetingsTableTableManager get meetings =>
      $$MeetingsTableTableManager(_db.attachedDatabase, _db.meetings);
  $$SpeakersTableTableManager get speakers =>
      $$SpeakersTableTableManager(_db.attachedDatabase, _db.speakers);
}
