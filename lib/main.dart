import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'store.dart';
import 'screens.dart';

void main() { WidgetsFlutterBinding.ensureInitialized(); runApp(const Bootstrap()); }
class Bootstrap extends StatefulWidget {
  const Bootstrap({super.key});
  @override State<Bootstrap> createState() => _BootstrapState();
}
class _BootstrapState extends State<Bootstrap> {
  late Future<(CoachStore,bool)> loading;
  @override void initState() { super.initState(); loading=load(); }
  Future<(CoachStore,bool)> load() async {
    final store=await CoachStore.open();
    try { await store.collectGarbage(); return (store,await store.consented()); }
    catch (_) { await store.close(); rethrow; }
  }
  @override Widget build(BuildContext context) => FutureBuilder<(CoachStore,bool)>(future:loading,builder:(context,snapshot){
    if(snapshot.hasData) { return CoachApp(store:snapshot.data!.$1,consented:snapshot.data!.$2); }
    return MaterialApp(home:Scaffold(body:Center(child:snapshot.hasError?
      Padding(padding:const EdgeInsets.all(24),child:Column(mainAxisSize:MainAxisSize.min,children:[
        const Text('未能開啟本機資料。請確認手機有足夠儲存空間。'), const SizedBox(height:16),
        FilledButton(onPressed:()=>setState(()=>loading=load()),child:const Text('重試')),
      ])):const CircularProgressIndicator())));
  });
}
class StoreScope extends InheritedNotifier<CoachStore> {
  const StoreScope({super.key,required CoachStore store,required super.child}):super(notifier:store);
  static CoachStore of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<StoreScope>()!.notifier!;
}
class CoachApp extends StatefulWidget {
  final CoachStore store; final bool consented;
  const CoachApp({super.key,required this.store,this.consented=false});
  @override State<CoachApp> createState()=>_CoachAppState();
}
class _CoachAppState extends State<CoachApp> {
  late bool accepted=widget.consented;
  @override Widget build(BuildContext context)=>StoreScope(store:widget.store,child:MaterialApp(
    title:'Badminton AI Coach',debugShowCheckedModeBanner:false,
    locale:const Locale('zh','HK'),supportedLocales:const [Locale('zh','HK'),Locale('zh','TW'),Locale('en')],
    localizationsDelegates:GlobalMaterialLocalizations.delegates,
    theme:ThemeData(useMaterial3:true,brightness:Brightness.light,
      colorScheme:ColorScheme.fromSeed(seedColor:const Color(0xff087f70)),
      scaffoldBackgroundColor:const Color(0xfff5f8f7),
      inputDecorationTheme:const InputDecorationTheme(border:OutlineInputBorder()),
    ),
    home:accepted?const HomeShell():ConsentScreen(onAccept:() async {
      await widget.store.consent(); if(mounted) { setState(()=>accepted=true); }
    }),
  ));
}
