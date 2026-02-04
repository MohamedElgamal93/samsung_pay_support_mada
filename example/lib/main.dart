import 'package:flutter/material.dart';
import 'package:samsung_pay_sdk_flutter/model/amount_box_control.dart';
import 'package:samsung_pay_sdk_flutter/model/custom_sheet.dart';
import 'package:samsung_pay_sdk_flutter/model/custom_sheet_payment_info.dart';
import 'package:samsung_pay_sdk_flutter/samsung_pay_sdk_flutter.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

void main() {
  runApp(const MaterialApp(home: MyHomePage(title: "In-App Payment"), debugShowCheckedModeBanner: false));
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // Set PartnerInfo to initialize SamsungPaySdkFlutter

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  var isAvailbelSamsungpay = false;

  @override
  void initState() {
    super.initState();

    checkSamsungPaystatus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Theme.of(context).colorScheme.inversePrimary, title: Text(widget.title)),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Card(
              child: Padding(
                padding: EdgeInsets.all(10.0),
                child: Column(
                  children: [
                    SizedBox(height: 10),
                    Row(
                      children: [
                        SizedBox(width: 60),
                        SizedBox(width: 20),
                        Text('SamsungPay', textAlign: TextAlign.left),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      //Add the Samsung Pay button in the bottom navigation bar
      bottomNavigationBar: InkWell(
        onTap: () async {
          final samsungPayService = SamsungPayService(serviceId: "samsungServiceId", amountTotal: 100.0, paymentBrands: ["mada", "visa", "masterCard", "discover", "americanExpress"]);
          var dataToken = await samsungPayService.requestPaymentWithSamsungWallet();
          print(dataToken);
        },
        child: Image.asset('assets/pay_rectangular_full_screen_black.png'),
      ),
    );
  }

  Future<void> checkSamsungPaystatus() async {
    if (Platform.isAndroid) {
      try {
        isAvailbelSamsungpay = await SamsungPayManager.isAvailable("serviceIdentifier"); // add here serviceIdentifier
      } catch (e, s) {
        debugPrint("SamsungPay ERROR: $e");
        debugPrintStack(stackTrace: s);
      }
    }
  }
}

class SamsungPayService {
  final String serviceId;
  double amountTotal;
  final List<String> paymentBrands;

  SamsungPayService({required this.serviceId, required this.amountTotal, required this.paymentBrands});

  List<Brand> get brandList {
    final brands = paymentBrands.map(brandFromString).whereType<Brand>().toList();

    return brands.isEmpty ? [Brand.VISA, Brand.MASTERCARD, Brand.AMERICANEXPRESS, Brand.DISCOVER, Brand.MADA] : brands;
  }

  static String currency = "SAR";
  static String AMOUNT_CONTROL_ID = "amountControlId";

  late final SamsungPaySdkFlutter samsungPaySdkFlutterPlugin = SamsungPaySdkFlutter(PartnerInfo(serviceId: serviceId, data: {SpaySdk.PARTNER_SERVICE_TYPE: ServiceType.INAPP_PAYMENT.name}));

  /// Convert callback API → Future<bool>
  Future<bool> checkSamsungPayStatus() {
    final completer = Completer<bool>();

    samsungPaySdkFlutterPlugin.getSamsungPayStatus(
      StatusListener(
        onSuccess: (status, bundle) {
          completer.complete(status == "2");
        },
        onFail: (errorCode, bundle) {
          completer.complete(false);
        },
      ),
    );

    return completer.future;
  }

  Future<String?> requestPaymentWithSamsungWallet() {
    final completer = Completer<String?>();

    samsungPaySdkFlutterPlugin.startInAppPayWithCustomSheet(
      makeTransactionDetailsWithSheet(),
      CustomSheetTransactionInfoListener(
        onCardInfoUpdated: (cardInfo, sheet) {
          samsungPaySdkFlutterPlugin.updateSheet(sheet);
        },
        onSuccess: (info, credential, extraData) {
          try {
            final Map<String, dynamic> jsonData = jsonDecode(credential);
            final String dataValue = jsonData['3DS']['data'];
            completer.complete(dataValue);
          } catch (e) {
            print("Failed to parse paymentCredential: $e");
            completer.completeError(e); // complete with error
          }
        },
        onFail: (errorCode, bundle) {
          print("Payment Failed: $errorCode");
          completer.completeError("Payment Failed: $errorCode");
        },
      ),
    );

    return completer.future;
  }

  CustomSheetPaymentInfo makeTransactionDetailsWithSheet() {
    final extraPaymentInfo = <String, dynamic>{SpaySdk.EXTRA_CRYPTOGRAM_TYPE: 'NONE', SpaySdk.EXTRA_ACCEPT_COMBO_CARD: false, SpaySdk.EXTRA_REQUIRE_CPF: false};

    final paymentInfo = CustomSheetPaymentInfo(merchantName: "Blu app", customSheet: makeUpCustomSheet());

    paymentInfo.merchantId = "samsungMerchantId"; // needed it be added
    paymentInfo.setOrderNumber(getRandomNumber(length: 10));
    paymentInfo.setMerchantCountryCode("SA");
    paymentInfo.addressInPaymentSheet = AddressInPaymentSheet.DO_NOT_SHOW;
    paymentInfo.allowedCardBrand = brandList;
    paymentInfo.setCardHolderNameEnabled(false);
    paymentInfo.setExtraPaymentInfo(extraPaymentInfo);

    return paymentInfo;
  }

  String getRandomNumber({int length = 10}) {
    final rng = Random();
    return List.generate(length, (_) => rng.nextInt(10)).join();
  }

  CustomSheet makeUpCustomSheet() {
    final sheet = CustomSheet();
    sheet.addControl(makeAmountControl());
    return sheet;
  }

  AmountBoxControl makeAmountControl() {
    final control = AmountBoxControl(AMOUNT_CONTROL_ID, currency);
    control.setAmountTotal(amountTotal, SpaySdk.FORMAT_TOTAL_PRICE_ONLY);
    return control;
  }

  Brand? brandFromString(String brand) {
    switch (brand) {
      case "visa":
        return Brand.VISA;
      case "masterCard":
        return Brand.MASTERCARD;
      case "mada":
        return Brand.MADA;

      case "americanExpress":
      case "amex":
        return Brand.AMERICANEXPRESS;

      case "discover":
        return Brand.DISCOVER;

      default:
        return null;
    }
  }
}

class SamsungPayManager {
  static bool? _available;

  static Future<bool> isAvailable(String id) async {
    if (_available != null) return _available!;

    final service = SamsungPayService(serviceId: id, amountTotal: 1, paymentBrands: ["mada", "visa", "masterCard", "americanExpress", "amex", "discover"]);

    _available = await service.checkSamsungPayStatus();
    return _available!;
  }
}
