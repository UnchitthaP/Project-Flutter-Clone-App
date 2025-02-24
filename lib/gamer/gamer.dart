import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tetris/gamer/block.dart';
import 'package:tetris/main.dart';
import 'package:tetris/material/audios.dart';

///the height of game pad
const GAME_PAD_MATRIX_H = 20;

///the width of game pad
const GAME_PAD_MATRIX_W = 10;

///state of [GameControl]
enum GameStates {
  ///คุณสามารถเริ่มเกม Tetris ที่น่าตื่นเต้นและน่าตื่นเต้นได้ตลอดเวลา
  none,

  ///ขณะที่เกมหยุดชั่วคราว บล็อกที่ตกลงมาจะหยุดลง
  paused,

  ///เกมกำลังดำเนินอยู่และบล็อกกำลังพัง
  ///ปุ่มเป็นแบบโต้ตอบ
  running,

  ///เกมกำลังรีเซ็ต
  ///หลังจากรีเซ็ตเสร็จแล้ว，[GameController]สถานะจะถูกย้ายไปยัง[none]
  reset,

  ///บล็อกที่ตกลงมาถึงด้านล่างแล้ว และตอนนี้กำลังได้รับการแก้ไขในเมทริกซ์เกม
  ///หลังจากการแก้ไขเสร็จสิ้น ภารกิจการล้มของบล็อกถัดไปจะเริ่มทันที
  mixing,

  ///การกำจัดแถว
  ///หลังจากการกำจัดเสร็จสิ้น ภารกิจการล้มของบล็อกถัดไปจะเริ่มทันที
  clear,

  ///บล็อกตกลงไปด้านล่างอย่างรวดเร็ว
  drop,
}

class Game extends StatefulWidget {
  final Widget child;

  const Game({Key? key, required this.child}) : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return GameControl();
  }

  static GameControl of(BuildContext context) {
    final state = context.findAncestorStateOfType<GameControl>();
    assert(state != null, "must wrap this context with [Game]");
    return state!;
  }
}

///duration for show a line when reset
const _REST_LINE_DURATION = const Duration(milliseconds: 50);

const _LEVEL_MAX = 6;

const _LEVEL_MIN = 1;

const _SPEED = [
  const Duration(milliseconds: 800),
  const Duration(milliseconds: 650),
  const Duration(milliseconds: 500),
  const Duration(milliseconds: 370),
  const Duration(milliseconds: 250),
  const Duration(milliseconds: 160),
];

class GameControl extends State<Game> with RouteAware {
  GameControl() {
    //inflate game pad data
    for (int i = 0; i < GAME_PAD_MATRIX_H; i++) {
      _data.add(List.filled(GAME_PAD_MATRIX_W, 0));
      _mask.add(List.filled(GAME_PAD_MATRIX_W, 0));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPushNext() {
    //pause when screen is at background
    pause();
  }

  ///the gamer data
  final List<List<int>> _data = [];

  ///มีอยู่[build] วิธีการใน [_data]ผสมเพื่อสร้างเมทริกซ์ใหม่
  ///[_mask]ความกว้างและความสูงของเมทริกซ์ [_data] สม่ำเสมอ
  ///เพื่อสิ่งใดๆ _mask[x,y] ：
  /// หากมีค่าเป็น 0,ถ้าอย่างนั้นก็ใช่ [_data]ไม่มีผลกระทบ
  /// หากมีค่าเป็น -1,วิธี [_data] บรรทัดนี้ไม่แสดง
  /// หากมีค่าเป็น 1，วิธี [_data] เน้นแถว
  final List<List<int>> _mask = [];

  ///from 1-6
  int _level = 1;

  int _points = 0;

  int _cleared = 0;

  Block? _current;

  Block _next = Block.getRandom();

  GameStates _states = GameStates.none;

  Block _getNext() {
    final next = _next;
    _next = Block.getRandom();
    return next;
  }

  SoundState get _sound => Sound.of(context);

  void rotate() {
    if (_states == GameStates.running) {
      final next = _current?.rotate();
      if (next != null && next.isValidInMatrix(_data)) {
        _current = next;
        _sound.rotate();
      }
    }
    setState(() {});
  }

  void right() {
    if (_states == GameStates.none && _level < _LEVEL_MAX) {
      _level++;
    } else if (_states == GameStates.running) {
      final next = _current?.right();
      if (next != null && next.isValidInMatrix(_data)) {
        _current = next;
        _sound.move();
      }
    }
    setState(() {});
  }

  void left() {
    if (_states == GameStates.none && _level > _LEVEL_MIN) {
      _level--;
    } else if (_states == GameStates.running) {
      final next = _current?.left();
      if (next != null && next.isValidInMatrix(_data)) {
        _current = next;
        _sound.move();
      }
    }
    setState(() {});
  }

  void drop() async {
    if (_states == GameStates.running) {
      for (int i = 0; i < GAME_PAD_MATRIX_H; i++) {
        final fall = _current?.fall(step: i + 1);
        if (fall != null && !fall.isValidInMatrix(_data)) {
          _current = _current?.fall(step: i);
          _states = GameStates.drop;
          setState(() {});
          await Future.delayed(const Duration(milliseconds: 100));
          _mixCurrentIntoData(mixSound: _sound.fall);
          break;
        }
      }
      setState(() {});
    } else if (_states == GameStates.paused || _states == GameStates.none) {
      _startGame();
    }
  }

  void down({bool enableSounds = true}) {
    if (_states == GameStates.running) {
      final next = _current?.fall();
      if (next != null && next.isValidInMatrix(_data)) {
        _current = next;
        if (enableSounds) {
          _sound.move();
        }
      } else {
        _mixCurrentIntoData();
      }
    }
    setState(() {});
  }

  Timer? _autoFallTimer;

  ///mix current into [_data]
  Future<void> _mixCurrentIntoData({VoidCallback? mixSound}) async {
    if (_current == null) {
      return;
    }
    //cancel the auto falling task
    _autoFall(false);

    _forTable((i, j) => _data[i][j] = _current?.get(j, i) ?? _data[i][j]);

    //กำจัดแถว
    final clearLines = [];
    for (int i = 0; i < GAME_PAD_MATRIX_H; i++) {
      if (_data[i].every((d) => d == 1)) {
        clearLines.add(i);
      }
    }

    if (clearLines.isNotEmpty) {
      setState(() => _states = GameStates.clear);

      _sound.clear();

      ///ลบภาพเคลื่อนไหวเอฟเฟกต์
      for (int count = 0; count < 5; count++) {
        clearLines.forEach((line) {
          _mask[line].fillRange(0, GAME_PAD_MATRIX_W, count % 2 == 0 ? -1 : 1);
        });
        setState(() {});
        await Future.delayed(Duration(milliseconds: 100));
      }
      clearLines
          .forEach((line) => _mask[line].fillRange(0, GAME_PAD_MATRIX_W, 0));

      //ลบแถวที่ตัดออกทั้งหมด
      clearLines.forEach((line) {
        _data.setRange(1, line + 1, _data);
        _data[0] = List.filled(GAME_PAD_MATRIX_W, 0);
      });
      debugPrint("clear lines : $clearLines");

      _cleared += clearLines.length;
      _points += clearLines.length * _level * 5;

      //up level possible when cleared
      int level = (_cleared ~/ 50) + _LEVEL_MIN;
      _level = level <= _LEVEL_MAX && level > _level ? level : _level;
    } else {
      _states = GameStates.mixing;
      mixSound?.call();
      _forTable((i, j) => _mask[i][j] = _current?.get(j, i) ?? _mask[i][j]);
      setState(() {});
      await Future.delayed(const Duration(milliseconds: 200));
      _forTable((i, j) => _mask[i][j] = 0);
      setState(() {});
    }

    //_currentบูรณาการเรียบร้อยแล้ว_data了，ดังนั้นจึงไม่จำเป็นอีกต่อไป
    _current = null;

    //ตรวจสอบว่าเกมจบแล้วหรือไม่ คือ ตรวจสอบว่ามีองค์ประกอบในแถวแรกที่เป็น 1 หรือไม่
    if (_data[0].contains(1)) {
      reset();
      return;
    } else {
      //เกมยังไม่จบ เริ่มรอบถัดไปของการล้มบล็อก
      _startGame();
    }
  }

  ///ข้ามไป
  ///i สำหรับ row
  ///j สำหรับ column
  static void _forTable(dynamic function(int row, int column)) {
    for (int i = 0; i < GAME_PAD_MATRIX_H; i++) {
      for (int j = 0; j < GAME_PAD_MATRIX_W; j++) {
        final b = function(i, j);
        if (b is bool && b) {
          break;
        }
      }
    }
  }

  void _autoFall(bool enable) {
    if (!enable) {
      _autoFallTimer?.cancel();
      _autoFallTimer = null;
    } else if (enable) {
      _autoFallTimer?.cancel();
      _current = _current ?? _getNext();
      _autoFallTimer = Timer.periodic(_SPEED[_level - 1], (t) {
        down(enableSounds: false);
      });
    }
  }

  void pause() {
    if (_states == GameStates.running) {
      _states = GameStates.paused;
    }
    setState(() {});
  }

  void pauseOrResume() {
    if (_states == GameStates.running) {
      pause();
    } else if (_states == GameStates.paused || _states == GameStates.none) {
      _startGame();
    }
  }

  void reset() {
    if (_states == GameStates.none) {
      //สามารถเริ่มเกมได้
      _startGame();
      return;
    }
    if (_states == GameStates.reset) {
      return;
    }
    _sound.start();
    _states = GameStates.reset;
    () async {
      int line = GAME_PAD_MATRIX_H;
      await Future.doWhile(() async {
        line--;
        for (int i = 0; i < GAME_PAD_MATRIX_W; i++) {
          _data[line][i] = 1;
        }
        setState(() {});
        await Future.delayed(_REST_LINE_DURATION);
        return line != 0;
      });
      _current = null;
      _getNext();
      _points = 0;
      _cleared = 0;
      await Future.doWhile(() async {
        for (int i = 0; i < GAME_PAD_MATRIX_W; i++) {
          _data[line][i] = 0;
        }
        setState(() {});
        line++;
        await Future.delayed(_REST_LINE_DURATION);
        return line != GAME_PAD_MATRIX_H;
      });
      setState(() {
        _states = GameStates.none;
      });
    }();
  }

  void _startGame() {
    if (_states == GameStates.running && _autoFallTimer?.isActive == false) {
      return;
    }
    _states = GameStates.running;
    _autoFall(true);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    List<List<int>> mixed = [];
    for (var i = 0; i < GAME_PAD_MATRIX_H; i++) {
      mixed.add(List.filled(GAME_PAD_MATRIX_W, 0));
      for (var j = 0; j < GAME_PAD_MATRIX_W; j++) {
        int value = _current?.get(j, i) ?? _data[i][j];
        if (_mask[i][j] == -1) {
          value = 0;
        } else if (_mask[i][j] == 1) {
          value = 2;
        }
        mixed[i][j] = value;
      }
    }
    debugPrint("game states : $_states");
    return GameState(
        mixed, _states, _level, _sound.mute, _points, _cleared, _next,
        child: widget.child);
  }

  void soundSwitch() {
    setState(() {
      _sound.mute = !_sound.mute;
    });
  }
}

class GameState extends InheritedWidget {
  GameState(
    this.data,
    this.states,
    this.level,
    this.muted,
    this.points,
    this.cleared,
    this.next, {
    Key? key,
    required this.child,
  }) : super(key: key, child: child);

  final Widget child;

  ///ข้อมูลการแสดงผลหน้าจอ
  ///0: อิฐเปล่า
  ///1: อิฐธรรมดา
  ///2: ไฮไลท์อิฐ
  final List<List<int>> data;

  final GameStates states;

  final int level;

  final bool muted;

  final int points;

  final int cleared;

  final Block next;

  static GameState of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<GameState>()!;
  }

  @override
  bool updateShouldNotify(GameState oldWidget) {
    return true;
  }
}
