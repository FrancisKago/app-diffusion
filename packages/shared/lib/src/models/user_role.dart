enum UserRole {
  admin,
  manager;

  String get dbValue => name;

  static UserRole fromString(String value) {
    return switch (value) {
      'admin' => UserRole.admin,
      'manager' => UserRole.manager,
      _ => throw ArgumentError.value(value, 'value', 'unknown role'),
    };
  }
}
