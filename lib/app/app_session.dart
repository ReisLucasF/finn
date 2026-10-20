import 'package:finan/domain/entities/user.dart';
import 'package:flutter/material.dart';

class AppSession extends ChangeNotifier {
  AppSession(this.user);

  AppUser user;

  void setUser(AppUser value) {
    user = value;
    notifyListeners();
  }
}
