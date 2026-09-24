import 'package:fetch_client/fetch_client.dart';
import 'package:http/http.dart' as http;

// 웹: 응답을 받는 대로 읽을 수 있는 fetch 방식 (기본 http 는 한 번에만 받는다)
http.Client createStreamingClient() => FetchClient(mode: RequestMode.cors);
