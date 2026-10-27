import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'main.dart';
import 'screens.dart';
import 'store.dart';

class MediaBridge {
  static const channel=MethodChannel('hk.badminton.coach/media');
  static Future<Map<String,dynamic>?> importVideo()=>channel.invokeMapMethod<String,dynamic>('importVideo');
  static Future<Map<String,dynamic>> info(String path) async => (await channel.invokeMapMethod<String,dynamic>('info',{'path':path}))!;
  static Future<Map<String,dynamic>> frame(String path,{int? index,int position=0}) async => (await channel.invokeMapMethod<String,dynamic>('frame',{'path':path,'index':index,'position':position}))!;
  static Future<String> directory() async => (await channel.invokeMethod<String>('directory'))!;
  static Future<bool> export(String path) async => await channel.invokeMethod<bool>('exportImage',{'path':path})??false;
}
String timeLabel(int ms){final seconds=ms~/1000;return '${seconds~/60}:${(seconds%60).toString().padLeft(2,'0')}.${((ms%1000)~/10).toString().padLeft(2,'0')}';}
int closestFrame(List<int> times,int position){
  if(times.isEmpty){return -1;}int low=0,high=times.length;
  while(low<high){final mid=(low+high)~/2;if(times[mid]<position){low=mid+1;}else{high=mid;}}
  if(low==0){return 0;}if(low==times.length){return low-1;}
  return position-times[low-1]<=times[low]-position?low-1:low;
}

class VideosScreen extends StatefulWidget {
  final String? studentId; const VideosScreen({super.key,this.studentId});
  @override State<VideosScreen> createState()=>_VideosState();
}
class _VideosState extends State<VideosScreen> {
  bool busy=false;
  Future<void> importLocalVideo() async {
    final store=StoreScope.of(context);String? studentId=widget.studentId;
    setState(()=>busy=true);
    try {
      if(studentId==null){final students=await store.students();if(!mounted){return;}if(students.isEmpty){message(context,'請先新增學員，再匯入影片。');return;}
        studentId=await showDialog<String>(context:context,builder:(c)=>SimpleDialog(title:const Text('影片屬於邊位學員？'),children:students.map((s)=>SimpleDialogOption(onPressed:()=>Navigator.pop(c,s['id'] as String),child:Padding(padding:const EdgeInsets.all(8),child:Text('${s['name']}')))).toList()));
      }
      if(studentId==null){return;}
      final media=await MediaBridge.importVideo();if(media==null){return;}
      final path=media['path'] as String;
      try{await store.addVideo({'id':newId(),'student_id':studentId,'title':media['name'] as String,'path':path,'duration_ms':media['duration'] as int,'created':now()});}
      catch(_){try{await File(path).delete();}on FileSystemException{/* Private orphan can be removed when app is uninstalled. */}rethrow;}
      if(mounted){message(context,'影片已複製到本機私人儲存。');}
    }catch(e){if(mounted){message(context,'匯入未完成：$e');}}
    finally{if(mounted){setState(()=>busy=false);}}
  }
  @override Widget build(BuildContext c)=>Column(children:[
    Padding(padding:const EdgeInsets.all(16),child:SizedBox(width:double.infinity,child:FilledButton.icon(onPressed:busy?null:importLocalVideo,icon:const Icon(Icons.video_file_outlined),label:Text(busy?'正在匯入…':'匯入手機影片')))),
    const Padding(padding:EdgeInsets.symmetric(horizontal:20),child:Text('每段最多 3 分鐘／300 MiB；影片只存喺呢部手機。')),
    Expanded(child:QueryList(future:StoreScope.of(c).videos(studentId:widget.studentId),builder:(rows)=>rows.isEmpty?const Center(child:EmptyPanel('逐段睇，逐點改善','匯入全身清晰入鏡嘅影片，慢放、逐格觀察，再記錄教練評估。')):ListView(padding:const EdgeInsets.all(16),children:rows.map((v)=>Card(child:ListTile(leading:const Icon(Icons.play_circle_outline,size:38),title:Text('${v['title']}',maxLines:2,overflow:TextOverflow.ellipsis),subtitle:Text('${v['student_name']}・${timeLabel(v['duration_ms'] as int)}'),onTap:()=>go(c,VideoScreen(v))))).toList()))),
  ]);
}
class VideoScreen extends StatefulWidget {
  final DbRow video; const VideoScreen(this.video,{super.key});
  @override State<VideoScreen> createState()=>_VideoState();
}
class _VideoState extends State<VideoScreen> with WidgetsBindingObserver {
  late final VideoPlayerController controller=VideoPlayerController.file(File(widget.video['path'] as String));
  late final Future<void> ready=controller.initialize();double speed=1;bool operation=false;
  @override void initState(){super.initState();WidgetsBinding.instance.addObserver(this);}
  @override void didChangeAppLifecycleState(AppLifecycleState state){if(state!=AppLifecycleState.resumed){controller.pause();}}
  @override void dispose(){WidgetsBinding.instance.removeObserver(this);controller.dispose();super.dispose();}
  Future<void> review() async {if(operation){return;}setState(()=>operation=true);try{await controller.pause();if(!mounted){return;}await Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>FrameScreen(video:widget.video,position:controller.value.position.inMilliseconds)));}catch(e){if(mounted){message(context,'未能開啟逐格檢視：$e');}}finally{if(mounted){setState(()=>operation=false);}}}
  @override Widget build(BuildContext c)=>Scaffold(appBar:AppBar(title:Text('${widget.video['title']}'),actions:[IconButton(tooltip:'刪除影片',onPressed:operation?null:() async {final store=StoreScope.of(c);await controller.pause();if(!c.mounted){return;}final yes=await confirm(c,'刪除影片？','影片及其標記截圖會從 App 刪除。既有教練評估及練習紀錄會保留。');if(yes&&c.mounted&&await perform(c,()=>store.deleteVideo(widget.video['id'] as String))&&c.mounted){Navigator.pop(c);}},icon:const Icon(Icons.delete_outline))]),body:FutureBuilder<void>(future:ready,builder:(ctx,s){
    if(s.hasError){return const Center(child:EmptyPanel('影片未能播放','手機可能不支援此影片格式。可嘗試 MP4 H.264 影片。'));}
    if(s.connectionState!=ConnectionState.done){return const Center(child:CircularProgressIndicator());}
    return ListView(padding:const EdgeInsets.all(16),children:[
      ClipRRect(borderRadius:BorderRadius.circular(16),child:ColoredBox(color:Colors.black,child:AspectRatio(aspectRatio:controller.value.aspectRatio>0?controller.value.aspectRatio:16/9,child:VideoPlayer(controller)))),
      ValueListenableBuilder<VideoPlayerValue>(valueListenable:controller,builder:(c,v,child)=>Column(children:[
        Slider(min:0,max:v.duration.inMilliseconds.toDouble().clamp(1,double.infinity),value:v.position.inMilliseconds.toDouble().clamp(0,v.duration.inMilliseconds.toDouble().clamp(1,double.infinity)),onChanged:(x)=>controller.seekTo(Duration(milliseconds:x.round()))),
        Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Text('${timeLabel(v.position.inMilliseconds)} / ${timeLabel(v.duration.inMilliseconds)}'),IconButton.filled(tooltip:v.isPlaying?'暫停':'播放',onPressed:()=>perform(c,() async {if(v.isPlaying){await controller.pause();}else{if(v.position>=v.duration){await controller.seekTo(Duration.zero);}await controller.play();}}),icon:Icon(v.isPlaying?Icons.pause:Icons.play_arrow))]),
        if(v.hasError) Text('播放錯誤：${v.errorDescription}'),
      ])),
      Wrap(spacing:8,children:[.25,.5,.75,1.0].map((v)=>ChoiceChip(label:Text('${v}x'),selected:speed==v,onSelected:operation?null:(_)=>perform(c,() async {await controller.setPlaybackSpeed(v);if(mounted){setState(()=>speed=v);}}))).toList()),const SizedBox(height:16),
      FilledButton.icon(onPressed:operation?null:review,icon:const Icon(Icons.draw_outlined),label:const Text('逐格／截圖及畫線')),
      OutlinedButton.icon(onPressed:()=>perform(c,() async {await controller.pause();if(c.mounted){go(c,AssessmentScreen(studentId:widget.video['student_id'] as String,videoId:widget.video['id'] as String));}}),icon:const Icon(Icons.fact_check_outlined),label:const Text('記錄教練評估')),const SizedBox(height:20),
      Text('已儲存標記',style:Theme.of(c).textTheme.titleLarge),
      QueryList(future:StoreScope.of(c).snapshots(widget.video['id'] as String),builder:(rows)=>Column(children:rows.isEmpty?[const Padding(padding:EdgeInsets.all(20),child:Text('暫時未有截圖'))]:rows.map((r)=>Card(child:ListTile(leading:const Icon(Icons.image_outlined),title:Text('${timeLabel(r['position_ms'] as int)}・${(r['frame_index'] as int)<0?'時間擷取':'第 ${(r['frame_index'] as int)+1} 格'}'),subtitle:Text(dateLabel(r['created'])),onTap:()=>go(c,SnapshotScreen(r))))).toList())),
    ]);
  }));
}
class FrameScreen extends StatefulWidget {
  final DbRow video;final int position;
  const FrameScreen({super.key,required this.video,required this.position});
  @override State<FrameScreen> createState()=>_FrameState();
}
class _FrameState extends State<FrameScreen> {
  final boundary=GlobalKey(); List<int> times=[];Map<String,dynamic>? frame;String? error;bool loading=true,saving=false,precise=false,dirty=false;
  int index=-1;final lines=<List<Offset>>[];List<Offset>? current;
  String get path=>widget.video['path'] as String;
  @override void initState(){super.initState();initialize();}
  Future<void> initialize() async {
    try{final info=await MediaBridge.info(path);precise=info['precise']==true;times=(info['times'] as List? ?? []).map((x)=>(x as num).toInt()).toList();index=precise?closestFrame(times,widget.position):-1;await fetch(index);}
    catch(e){if(mounted){setState((){error='$e';loading=false;});}}
  }
  Future<void> fetch(int target) async {
    if(mounted){setState((){loading=true;error=null;});}
    try{final result=await MediaBridge.frame(path,index:target>=0?target:null,position:widget.position);if(mounted){setState((){frame=result;index=(result['index'] as num).toInt();lines.clear();current=null;dirty=false;loading=false;});}}
    catch(e){if(mounted){setState((){error='$e';loading=false;});}}
  }
  Future<bool> discard() async {
    if(!dirty){return true;}
    return await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('放棄未儲存畫線？'),content:const Text('轉到另一影格或離開會清除今次未儲存標記。'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('繼續標記')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('放棄標記'))]))??false;
  }
  Future<void> save() async {
    if(frame==null||loading||saving){return;}final store=StoreScope.of(context);setState(()=>saving=true);
    String? output;
    try{
      await WidgetsBinding.instance.endOfFrame;if(!mounted){return;}
      final render=boundary.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if(render==null){throw StateError('影像尚未就緒');}
      final image=await render.toImage(pixelRatio:2);Uint8List bytes;
      try{final data=await image.toByteData(format:ui.ImageByteFormat.png);if(data==null){throw StateError('圖片編碼失敗');}bytes=data.buffer.asUint8List();}finally{image.dispose();}
      final dir=await MediaBridge.directory();output='$dir/mark_${newId()}.png';await File(output).writeAsBytes(bytes,flush:true);
      await store.addSnapshot({'id':newId(),'video_id':widget.video['id'],'path':output,'position_ms':(frame!['position'] as num).toInt(),'frame_index':index,'strokes':jsonEncode(lines.map((line)=>line.map((pt)=>[pt.dx,pt.dy]).toList()).toList()),'created':now()});
      output=null;if(mounted){setState(()=>dirty=false);message(context,'已儲存標記截圖');}
    }catch(e){if(output!=null){try{await File(output).delete();}on FileSystemException{/* Preserve error report. */}}if(mounted){message(context,'儲存未完成：$e');}}
    finally{if(mounted){setState(()=>saving=false);}}
  }
  @override Widget build(BuildContext c)=>PopScope(canPop:!dirty&&!saving,onPopInvokedWithResult:(didPop,result) async {if(didPop||saving){return;}if(await discard()&&mounted){setState(()=>dirty=false);WidgetsBinding.instance.addPostFrameCallback((_){if(mounted){Navigator.pop(context);}});}},child:Scaffold(appBar:AppBar(title:const Text('逐格及手動畫線')),body:ListView(padding:const EdgeInsets.all(16),children:[
    if(loading) const Padding(padding:EdgeInsets.all(32),child:Center(child:CircularProgressIndicator())),
    if(error!=null) Padding(padding:const EdgeInsets.all(16),child:Column(children:[Text('影格未能讀取：$error'),TextButton(onPressed:()=>fetch(index),child:const Text('重試'))])),
    if(frame!=null&&!loading) ...[
      Text(index<0?'時間擷取（近似位置）；此影片不支援可靠逐格。':'第 ${index+1} / ${times.length} 格・${timeLabel((frame!['position'] as num).toInt())}',style:const TextStyle(fontWeight:FontWeight.bold)),const SizedBox(height:12),
      AspectRatio(aspectRatio:(frame!['width'] as num)/(frame!['height'] as num),child:LayoutBuilder(builder:(ctx,box)=>RepaintBoundary(key:boundary,child:GestureDetector(
        onPanStart:saving?null:(d)=>setState((){current=[Offset((d.localPosition.dx/box.maxWidth).clamp(0,1),(d.localPosition.dy/box.maxHeight).clamp(0,1))];lines.add(current!);dirty=true;}),
        onPanUpdate:saving?null:(d)=>setState(()=>current?.add(Offset((d.localPosition.dx/box.maxWidth).clamp(0,1),(d.localPosition.dy/box.maxHeight).clamp(0,1)))),
        onPanEnd:saving?null:(_)=>setState(()=>current=null),
        child:Stack(fit:StackFit.expand,children:[Image.memory(frame!['bytes'] as Uint8List,fit:BoxFit.fill,gaplessPlayback:true),CustomPaint(painter:LinePainter(lines))]),
      )))),const SizedBox(height:12),const Text('用手指拖動畫線。換影格前請先儲存。'),
      Row(children:[Expanded(child:OutlinedButton.icon(onPressed:!precise||index<=0||saving?null:() async {if(await discard()&&mounted){await fetch(index-1);}},icon:const Icon(Icons.skip_previous),label:const Text('上一格'))),const SizedBox(width:12),Expanded(child:OutlinedButton.icon(onPressed:!precise||index<0||index>=times.length-1||saving?null:() async {if(await discard()&&mounted){await fetch(index+1);}},icon:const Icon(Icons.skip_next),label:const Text('下一格')))]),
      Wrap(spacing:12,children:[TextButton.icon(onPressed:lines.isEmpty||saving?null:()=>setState((){lines.removeLast();dirty=true;}),icon:const Icon(Icons.undo),label:const Text('撤銷')),TextButton.icon(onPressed:lines.isEmpty||saving?null:()=>setState((){lines.clear();dirty=true;}),icon:const Icon(Icons.clear),label:const Text('清除畫線'))]),
      FilledButton.icon(onPressed:saving?null:save,icon:const Icon(Icons.save_outlined),label:Text(saving?'儲存中…':'儲存截圖及標記')),
    ],
  ])));
}
class LinePainter extends CustomPainter {
  final List<List<Offset>> lines;LinePainter(this.lines);
  @override void paint(Canvas canvas,Size size){final paint=Paint()..color=Colors.amber..strokeWidth=3..style=PaintingStyle.stroke..strokeCap=StrokeCap.round..strokeJoin=StrokeJoin.round;
    for(final line in lines){if(line.isEmpty){continue;}if(line.length==1){canvas.drawCircle(Offset(line[0].dx*size.width,line[0].dy*size.height),1.5,Paint()..color=Colors.amber);continue;}
      final path=Path()..moveTo(line[0].dx*size.width,line[0].dy*size.height);for(final pt in line.skip(1)){path.lineTo(pt.dx*size.width,pt.dy*size.height);}canvas.drawPath(path,paint);
    }
  }
  @override bool shouldRepaint(covariant LinePainter oldDelegate)=>true;
}
class SnapshotScreen extends StatelessWidget {
  final DbRow record;const SnapshotScreen(this.record,{super.key});
  @override Widget build(BuildContext c)=>Scaffold(appBar:AppBar(title:const Text('已儲存標記')),body:Column(children:[Expanded(child:InteractiveViewer(minScale:.5,maxScale:5,child:Center(child:Image.file(File(record['path'] as String),errorBuilder:(c,e,s)=>const Text('圖片檔案已不存在'))))),Padding(padding:const EdgeInsets.all(20),child:Column(children:[Text('${timeLabel(record['position_ms'] as int)}・${dateLabel(record['created'])}'),const SizedBox(height:12),FilledButton.icon(onPressed:()=>perform(c,() async {final saved=await MediaBridge.export(record['path'] as String);if(c.mounted&&saved){message(c,'圖片已匯出，請妥善保管。');}}),icon:const Icon(Icons.save_alt),label:const Text('匯出標記圖片'))]))]));
}
