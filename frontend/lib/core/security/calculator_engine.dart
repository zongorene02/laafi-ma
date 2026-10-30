/// Calculatrice de camouflage : une VRAIE calculatrice (quelqu'un qui
/// l'essaie doit obtenir des résultats justes), qui sait en plus reconnaître
/// « code secret puis = ».
///
/// Logique pure, sans Flutter, pour être testée simplement.
class CalculatorEngine {
  static const plus = '+';
  static const minus = '−';
  static const times = '×';
  static const divide = '÷';
  static const equals = '=';
  static const clear = 'C';
  static const backspace = '⌫';
  static const dot = '.';

  static const operators = {plus, minus, times, divide};
  static const _maxDigits = 12;

  String _display = '0';
  double? _accumulator;
  String? _pendingOp;
  bool _fresh = true;

  /// Touches tapées depuis le dernier opérateur, « = » ou « C » : c'est là
  /// qu'on cherche un code secret.
  String _typed = '';

  /// Vrai si un opérateur a été utilisé depuis le dernier « C » ou « = ».
  bool _usedOperator = false;

  String get display => _display;
  String? get pendingOperator => _pendingOp;

  /// Applique une touche. Renvoie un CODE CANDIDAT quand « = » arrive juste
  /// après une suite de 4 à 6 chiffres sans aucun opérateur : à l'appelant de
  /// vérifier s'il s'agit du code secret. Dans tous les autres cas, `null`.
  String? press(String key) {
    if (RegExp(r'^\d$').hasMatch(key)) {
      _inputDigit(key);
      return null;
    }
    switch (key) {
      case dot:
        if (_fresh) {
          _display = '0.';
          _fresh = false;
        } else if (!_display.contains('.')) {
          _display = '$_display.';
        }
        _typed += '.';
        return null;
      case clear:
        _reset();
        return null;
      case backspace:
        if (!_fresh) {
          _display = _display.length <= 1 ? '0' : _display.substring(0, _display.length - 1);
          if (_display == '-' || _display.isEmpty) _display = '0';
          if (_typed.isNotEmpty) _typed = _typed.substring(0, _typed.length - 1);
        }
        return null;
      case equals:
        final candidate = (!_usedOperator && _pendingOp == null && RegExp(r'^\d{4,6}$').hasMatch(_typed))
            ? _typed
            : null;
        if (_pendingOp != null && _accumulator != null && !_fresh) {
          _display = _format(_apply(_accumulator!, _pendingOp!, _value));
        }
        _pendingOp = null;
        _accumulator = null;
        _fresh = true;
        _typed = '';
        _usedOperator = false;
        return candidate;
    }
    if (operators.contains(key)) {
      if (_pendingOp != null && _accumulator != null && !_fresh) {
        _display = _format(_apply(_accumulator!, _pendingOp!, _value));
      }
      _accumulator = _value;
      _pendingOp = key;
      _fresh = true;
      _typed = '';
      _usedOperator = true;
    }
    return null;
  }

  void _inputDigit(String digit) {
    if (_fresh || _display == '0') {
      _display = digit;
      _fresh = false;
    } else if (_display.replaceAll(RegExp(r'[^0-9]'), '').length < _maxDigits) {
      _display = '$_display$digit';
    }
    _typed += digit;
  }

  void _reset() {
    _display = '0';
    _accumulator = null;
    _pendingOp = null;
    _fresh = true;
    _typed = '';
    _usedOperator = false;
  }

  double get _value => double.tryParse(_display) ?? 0;

  double _apply(double a, String op, double b) => switch (op) {
    plus => a + b,
    minus => a - b,
    times => a * b,
    divide => b == 0 ? double.nan : a / b,
    _ => b,
  };

  String _format(double value) {
    if (value.isNaN || value.isInfinite) return 'Erreur';
    if (value == value.roundToDouble() && value.abs() < 1e12) return value.toInt().toString();
    var text = value.toStringAsPrecision(10);
    if (text.contains('e')) return text;
    if (text.contains('.')) {
      text = text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    }
    return text;
  }
}
