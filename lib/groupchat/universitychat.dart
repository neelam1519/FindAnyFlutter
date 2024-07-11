import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:findany_flutter/utils/sharedpreferences.dart';
import 'package:firebase_database/firebase_database.dart' as rtdb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:dash_chat_2/dash_chat_2.dart';
import 'package:findany_flutter/services/sendnotification.dart';
import 'package:findany_flutter/utils/utils.dart';
import 'package:url_launcher/url_launcher.dart';

class UniversityChat extends StatefulWidget {
  static bool isChatOpen = false;

  @override
  _UniversityChatState createState() => _UniversityChatState();
}

class _UniversityChatState extends State<UniversityChat> {
  Utils utils = Utils();
  NotificationService notificationService = NotificationService();
  SharedPreferences sharedPreferences = SharedPreferences();

  late rtdb.DatabaseReference _chatRef;
  late rtdb.DatabaseReference _onlineUsersRef;
  List<ChatMessage> _messages = [];
  ChatUser? _user;
  User? firebaseUser = FirebaseAuth.instance.currentUser;
  String? _lastMessageKey;
  bool _isLoadingMore = false;
  bool _isInitialLoadComplete = false;
  late StreamSubscription<rtdb.DatabaseEvent> _messageSubscription;
  late StreamSubscription<rtdb.DatabaseEvent> _onlineUsersSubscription;
  int _onlineUsersCount = 0;

  @override
  void initState() {
    super.initState();
    _chatRef = rtdb.FirebaseDatabase.instance.ref().child("chats");
    _onlineUsersRef = rtdb.FirebaseDatabase.instance.ref().child("onlineUsers");
    UniversityChat.isChatOpen = true;
    initializeUser().then((_) {
      listenForNewMessages();
      trackOnlineUsers();
      setUserOnline();
    });
  }

  @override
  void dispose() {
    _messageSubscription.cancel();
    _onlineUsersSubscription.cancel();
    setUserOffline();
    UniversityChat.isChatOpen = false;
    super.dispose();
  }

  Future<void> initializeUser() async {
    if (firebaseUser != null) {
      String email = firebaseUser!.email!;
      String userId = utils.removeEmailDomain(email);
      DocumentReference userRef = FirebaseFirestore.instance.doc('UserDetails/${utils.getCurrentUserUID()}');

      // Handle potential null values with default values
      String username = await sharedPreferences.getDataFromReference(userRef, "Username") ?? '';
      String displayName = utils.removeTextAfterFirstNumber(firebaseUser!.displayName ?? 'Anonymous');

      String name = username.isNotEmpty ? username : (displayName.isNotEmpty ? displayName : 'Anonymous');

      if (mounted) {
        setState(() {
          _user = ChatUser(
            id: userId,
            firstName: name,
          );
        });
      }
    }
  }

  void listenForNewMessages() {
    print('Listening For New Messages...');
    List<String?> keyList = [];
    _messageSubscription = _chatRef.orderByKey().limitToLast(20).onChildAdded.listen((event) {
      if (!mounted) return; // Prevent calling setState if the widget is not mounted
      rtdb.DataSnapshot snapshot = event.snapshot;
      var value = snapshot.value;
      keyList.add(snapshot.key);
      if (value is Map) {
        try {
          Map<String, dynamic> messageData = _convertToMapStringDynamic(value);
          if (mounted) {
            setState(() {
              _messages.insert(0, ChatMessage.fromJson(messageData));
            });
          }
        } catch (e) {
          print("Error parsing new message: $e");
        }
      }
      _lastMessageKey = keyList.first;
      print('Last Message: $_lastMessageKey');
    });

    _chatRef.once().then((event) {
      if (!event.snapshot.exists) {
        if (mounted) {
          setState(() {
            // Trigger a state update to show "No messages found"
            _isInitialLoadComplete = true;
            print("No messages found");
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isInitialLoadComplete = true;
          });
        }
      }
    }).catchError((error) {
      print("Error fetching messages: $error");
      if (mounted) {
        setState(() {
          _isInitialLoadComplete = true;
        });
      }
    });
  }

  void trackOnlineUsers() {
    _onlineUsersSubscription = _onlineUsersRef.onValue.listen((event) {
      if (!mounted) return;
      rtdb.DataSnapshot snapshot = event.snapshot;
      if (snapshot.exists) {
        Map<dynamic, dynamic> onlineUsers = snapshot.value as Map<dynamic, dynamic>;
        setState(() {
          _onlineUsersCount = onlineUsers.length;
        });
      } else {
        setState(() {
          _onlineUsersCount = 0;
        });
      }
    });
  }

  void setUserOnline() {
    if (firebaseUser != null) {
      String userId = firebaseUser!.uid;
      _onlineUsersRef.child(userId).set(true);
      _onlineUsersRef.child(userId).onDisconnect().remove();
    }
  }

  void setUserOffline() {
    if (firebaseUser != null) {
      String userId = firebaseUser!.uid;
      _onlineUsersRef.child(userId).remove();
    }
  }

  Future<void> loadMoreMessages() async {
    if (_isLoadingMore || _lastMessageKey == null) return;

    if (mounted) {
      setState(() {
        _isLoadingMore = true;
      });
    }

    print('Loading more messages from key: $_lastMessageKey');

    rtdb.Query query = _chatRef.orderByKey().endAt(_lastMessageKey).limitToLast(21); // Load 21 to account for the last message key overlap
    try {
      rtdb.DatabaseEvent event = await query.once();
      rtdb.DataSnapshot snapshot = event.snapshot;

      if (snapshot.exists) {
        List<ChatMessage> moreMessages = [];
        String? newLastMessageKey;
        snapshot.children.forEach((childSnapshot) {
          var value = childSnapshot.value;
          if (value is Map) {
            try {
              Map<String, dynamic> messageData = _convertToMapStringDynamic(value);
              ChatMessage chatMessage = ChatMessage.fromJson(messageData);
              if (childSnapshot.key != _lastMessageKey) {
                moreMessages.add(chatMessage);
              }
              newLastMessageKey = newLastMessageKey ?? childSnapshot.key;
            } catch (e) {
              print("Error parsing message: $e");
            }
          }
        });

        if (mounted) {
          setState(() {
            _messages.addAll(moreMessages.reversed.toList());
            _lastMessageKey = newLastMessageKey;
          });
        }
      }

      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    } catch (error) {
      print("Error loading more messages: $error");
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    }
  }

  Future<void> _handleSend(ChatMessage message) async {
    final newMessageRef = _chatRef.push();
    newMessageRef.set(message.toJson());
    List<String> tokens = await utils.getAllTokens();
    await notificationService.sendNotification(tokens, "Group Chat", message.text, {"source": 'UniversityChat'});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('University Chat'),
        actions: [
          if (_onlineUsersCount > 0)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Icon(Icons.circle, color: Colors.green, size: 12),
                  SizedBox(width: 5),
                  Text('$_onlineUsersCount'),
                ],
              ),
            ),
        ],
      ),
      body: _user == null
          ? Center(child: CircularProgressIndicator())
          : !_isInitialLoadComplete
          ? Center(child: CircularProgressIndicator())
          : _messages.isEmpty
          ? Center(child: Text('No messages found'))
          : DashChat(
        currentUser: _user!,
        onSend: _handleSend,
        messages: _messages,
        messageListOptions: MessageListOptions(
          onLoadEarlier: loadMoreMessages,
        ),
        inputOptions: InputOptions(),
        messageOptions: MessageOptions(
          parsePatterns: [
            MatchText(
              type: ParsedType.URL,
              style: TextStyle(
                color: Colors.blue,
                decoration: TextDecoration.underline,
              ),
              onTap: (url) async {
                if (await canLaunch(url)) {
                  await launch(url);
                } else {
                  throw 'Could not launch $url';
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Map<String, dynamic> _convertToMapStringDynamic(Map<dynamic, dynamic> original) {
    return original.map((key, value) {
      if (value is Map) {
        return MapEntry(key.toString(), _convertToMapStringDynamic(value));
      } else {
        return MapEntry(key.toString(), value);
      }
    });
  }
}
