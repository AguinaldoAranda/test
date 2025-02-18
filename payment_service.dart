import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pocket_pos/components/jumping_dot.dart';
import 'package:pocket_pos/cubit/pix_status/pix_status_cubit.dart';

import '../constants.dart';
import '../cubit/credit_card_option/credit_card_option_cubit.dart';
import '../cubit/credit_card_option/credit_card_option_state.dart';
import '../cubit/payment_flow/payment_flow_cubit.dart';
import '../cubit/payment_process/payment_process_cubit.dart';
import '../cubit/pix_status/pix_status_state.dart';
import '../cubit/serial_number/serial_number_cubit.dart';
import '../dto/payment_process_dto.dart';
import '../model/account.dart';
import '../model/credit_card_payment_options.dart';
import '../model/payment_pos_type.dart';
import '../model/pix_status.dart';
import '../model/pos_refund_response.dart';
import '../model/pos_response.dart';
import '../model/transaction_status.dart';
import '../model/transfer_account.dart';
import '../repositories/system_repository.dart';
import '../screens/financial/pos/components/receipt_widget.dart';
import '../screens/financial/pos/pos_list_screen.dart';
import '../screens/home/home_screen.dart';
import '../utils/functions_helper.dart';
import '../utils/number_utils.dart';
import '../utils/string_utils.dart';

class PaymentFlowService {
  /// Executa o fluxo de pagamento, retornando o resultado para a interface do usuário.
  static Future<void> executePaymentFlow({
    required BuildContext context,
    required Account account,
    required double txnAmount,
  }) async {
    String selectedPaymentType = '';
    int checkPixAttempts = 0;
    StateSetter? _bottomSheetState;
    String serialNumber = BlocProvider.of<SerialNumberCubit>(context).serialNumber;
    var _paymentFlowState = BlocProvider.of<PaymentFlowCubit>(context);

    // Lista de opções de pagamento
    final paymentOptions = {
      'CREDIT': account.enableCredit,
      'DEBIT': account.enableDebit,
      // 'PIX': account.enablePix,
    };

    if (_paymentFlowState.type != PaymentFlowType.transfer) {
      paymentOptions['PIX'] = account.enablePix;
    }

    // Filtra apenas as opções ativas
    final enabledPayments = paymentOptions.entries.where((entry) => entry.value).map((entry) => entry.key).toList();

    if (enabledPayments.length == 1) {
      // Apenas uma opção ativa, define automaticamente
      selectedPaymentType = enabledPayments.first;
    } else if (enabledPayments.length == 0) {
      FunctionsHelper.showModalBottomSheetMessage(
          context, 'Não há forma de pagamento habilitada, entre com contato o suporte Pocket.');
      return;
    } else {
      await showModalBottomSheet<String>(
        isScrollControlled: true,
        isDismissible: false,
        enableDrag: false,
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              _bottomSheetState = setState;

              return FractionallySizedBox(
                heightFactor: 0.5,
                child: Scaffold(
                  backgroundColor: Colors.transparent,
                  appBar: AppBar(
                    backgroundColor: Colors.transparent,
                    automaticallyImplyLeading: false,
                    elevation: 0,
                    title: Container(
                      padding: EdgeInsets.fromLTRB(0, 10, 10, 10),
                      child: Text(
                        'Selecione o método de pagamento',
                        style: AppTextStyles.titlesmall,
                      ),
                    ),
                    actions: [
                      IconButton(
                        onPressed: () async {
                          Navigator.pop(context);
                        },
                        icon: Icon(
                          Icons.close,
                          color: AppColors.neutrals00Bg,
                        ),
                      )
                    ],
                  ),
                  body: Center(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(kDefaultPaddingLeftRight, 0, kDefaultPaddingLeftRight, 0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const SizedBox(height: kDefaultPadding),
                          ...enabledPayments.map((paymentType) {
                            final label = paymentType == 'CREDIT'
                                ? 'Crédito'
                                : paymentType == 'DEBIT'
                                    ? 'Débito'
                                    : 'Pix';

                            return Column(
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: AppColors.neutrals700Main,
                                      width: 1,
                                    ),
                                  ),
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () {
                                      _bottomSheetState!(() {
                                        selectedPaymentType = paymentType;
                                      });
                                      Navigator.pop(context, paymentType);
                                    },
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: <Widget>[
                                        Radio<String>(
                                          value: paymentType,
                                          groupValue: selectedPaymentType,
                                          onChanged: (value) {
                                            setState(() {
                                              selectedPaymentType = value!;
                                            });
                                            Navigator.pop(context, value);
                                          },
                                          fillColor: MaterialStateProperty.resolveWith<Color>(
                                            (Set<MaterialState> states) {
                                              return AppColors.payFinancegreen300Main;
                                            },
                                          ),
                                        ),
                                        const SizedBox(width: kDefaultPadding),
                                        Expanded(
                                          child: Text(
                                            label,
                                            style: AppTextStyles.bodymedium,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: kDefaultPadding),
                              ],
                            );
                          }).toList(),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      );

      if (selectedPaymentType == null || selectedPaymentType == '') {
        return;
      }
    }

    // if (account.enableCredit && account.enableDebit) {
    //   // PaymentPosType? paymentPosType = await showModalBottomSheet<PaymentPosType>(
    //   await showModalBottomSheet<String>(
    //     isScrollControlled: true,
    //     isDismissible: false,
    //     enableDrag: false,
    //     context: context,
    //     builder: (context) {
    //       return StatefulBuilder(
    //         builder: (BuildContext context, StateSetter setState) {
    //           // _bottomSheetState = setState;
    //
    //           return FractionallySizedBox(
    //             heightFactor: 0.4,
    //             child: Scaffold(
    //               backgroundColor: Colors.transparent,
    //               appBar: AppBar(
    //                 backgroundColor: Colors.transparent,
    //                 automaticallyImplyLeading: false,
    //                 elevation: 0,
    //                 title: Container(
    //                   padding: EdgeInsets.fromLTRB(0, 10, 10, 10),
    //                   child: Text('Selecione o método de pagamento', style: AppTextStyles.titlesmall),
    //                 ),
    //                 actions: [
    //                   IconButton(
    //                     onPressed: () async {
    //                       setState(() {
    //                         selectedPaymentType = '';
    //                       });
    //                       Navigator.pop(context);
    //                     },
    //                     icon: Icon(
    //                       Icons.close,
    //                       color: AppColors.neutrals00Bg,
    //                     ),
    //                   )
    //                 ],
    //               ),
    //               body: Center(
    //                 child: SingleChildScrollView(
    //                   padding: EdgeInsets.fromLTRB(kDefaultPaddingLeftRight, 0, kDefaultPaddingLeftRight, 0),
    //                   child: Column(
    //                     mainAxisSize: MainAxisSize.min,
    //                     mainAxisAlignment: MainAxisAlignment.center,
    //                     crossAxisAlignment: CrossAxisAlignment.center,
    //                     children: [
    //                       const SizedBox(
    //                         height: kDefaultPadding,
    //                       ),
    //                       Container(
    //                         decoration: BoxDecoration(
    //                           borderRadius: BorderRadius.circular(8),
    //                           border: Border.all(
    //                             color: AppColors.neutrals700Main,
    //                             width: 1,
    //                           ),
    //                         ),
    //                         child: GestureDetector(
    //                           behavior: HitTestBehavior.opaque, // Garante que os eventos de toque sejam registrados no widget
    //                           onTap: () {
    //                             setState(() {
    //                               selectedPaymentType = 'CREDIT';
    //                             });
    //                             Navigator.pop(context, 'CREDIT');
    //                           },
    //                           child: Row(
    //                             crossAxisAlignment: CrossAxisAlignment.center,
    //                             children: <Widget>[
    //                               Radio<String>(
    //                                 value: 'CREDIT',
    //                                 groupValue: selectedPaymentType,
    //                                 onChanged: (value) {
    //                                   setState(() {
    //                                     selectedPaymentType = 'CREDIT';
    //                                   });
    //                                   Navigator.pop(context, 'CREDIT');
    //                                 },
    //                                 fillColor: MaterialStateProperty.resolveWith<Color>(
    //                                   (Set<MaterialState> states) {
    //                                     return AppColors.payFinancegreen300Main;
    //                                   },
    //                                 ),
    //                               ),
    //                               const SizedBox(width: kDefaultPadding),
    //                               Expanded(
    //                                 child: Text(
    //                                   'Crédito',
    //                                   style: AppTextStyles.bodymedium,
    //                                 ),
    //                               ),
    //                             ],
    //                           ),
    //                         ),
    //                       ),
    //                       const SizedBox(
    //                         height: kDefaultPadding,
    //                       ),
    //                       Container(
    //                         decoration: BoxDecoration(
    //                           borderRadius: BorderRadius.circular(8),
    //                           border: Border.all(
    //                             color: AppColors.neutrals700Main,
    //                             width: 1,
    //                           ),
    //                         ),
    //                         child: GestureDetector(
    //                           behavior: HitTestBehavior.opaque, // Garante que os eventos de toque sejam registrados no widget
    //                           onTap: () {
    //                             setState(() {
    //                               selectedPaymentType = 'DEBIT';
    //                               Navigator.pop(context, 'DEBIT');
    //                             });
    //                           },
    //                           child: Row(
    //                             crossAxisAlignment: CrossAxisAlignment.center,
    //                             children: <Widget>[
    //                               Radio<String>(
    //                                 value: 'DEBIT',
    //                                 groupValue: selectedPaymentType,
    //                                 onChanged: (value) {
    //                                   setState(() {
    //                                     selectedPaymentType = 'DEBIT';
    //                                   });
    //                                   Navigator.pop(context, 'DEBIT');
    //                                 },
    //                                 fillColor: MaterialStateProperty.resolveWith<Color>(
    //                                   (Set<MaterialState> states) {
    //                                     return AppColors.payFinancegreen300Main;
    //                                   },
    //                                 ),
    //                               ),
    //                               const SizedBox(width: kDefaultPadding),
    //                               Expanded(
    //                                 child: Text(
    //                                   'Débito',
    //                                   style: AppTextStyles.bodymedium,
    //                                 ),
    //                               ),
    //                             ],
    //                           ),
    //                         ),
    //                       ),
    //                       const SizedBox(
    //                         height: kDefaultPadding,
    //                       ),
    //                     ],
    //                   ),
    //                 ),
    //               ),
    //             ),
    //           );
    //         },
    //       );
    //     },
    //   );
    //
    //   if (selectedPaymentType == null || selectedPaymentType == '') {
    //     return;
    //   }
    // } else if (account.enableCredit && !account.enableDebit) {
    //   // setState(() {
    //   selectedPaymentType = 'CREDIT';
    //   // });
    // } else if (!account.enableCredit && account.enableDebit) {
    //   // setState(() {
    //   selectedPaymentType = 'DEBIT';
    //   // });
    // } else {
    //   FunctionsHelper.showModalBottomSheetMessage(
    //       context, 'Não há forma de pagamento habilitada, entre com contato o suporte Pocket.');
    //   return;
    // }

    /**
     * Verifica se há configuração para definir as parcelas com juros(InterestByInstallment).
     * Caso a configuração exista, não é necessário solicitar a definição do operador
     * sobre quem se responsabiliza pelos juros(loja x cliente).
     */
    String? installmentType;
    int interestByInstallment = account.interestByInstallment ?? 0;
    if (interestByInstallment <= 1 && selectedPaymentType != 'PIX'){
      installmentType = await showModalBottomSheet<String>(
        isScrollControlled: true,
        isDismissible: false,
        enableDrag: false,
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              _bottomSheetState = setState;

              return FractionallySizedBox(
                heightFactor: 0.5,
                child: Scaffold(
                  backgroundColor: Colors.transparent,
                  appBar: AppBar(
                    backgroundColor: Colors.transparent,
                    automaticallyImplyLeading: false,
                    elevation: 0,
                    title: Container(
                      padding: EdgeInsets.fromLTRB(0, 10, 10, 10),
                      child: Text(
                        'Quem paga os juros??',
                        style: AppTextStyles.titlesmall,
                      ),
                    ),
                    actions: [
                      IconButton(
                        onPressed: () async {
                          Navigator.pop(context);
                        },
                        icon: Icon(
                          Icons.close,
                          color: AppColors.neutrals00Bg,
                        ),
                      )
                    ],
                  ),
                  body: Center(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(kDefaultPaddingLeftRight, 0, kDefaultPaddingLeftRight, 0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const SizedBox(height: kDefaultPadding),
                          ...['Estabelecimento', 'Cliente'].map((paymentType) {
                            return Column(
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: AppColors.neutrals700Main,
                                      width: 1,
                                    ),
                                  ),
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () {
                                      Navigator.pop(context, paymentType);
                                    },
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: <Widget>[
                                        Radio<String>(
                                          value: paymentType,
                                          groupValue: selectedPaymentType,
                                          onChanged: (value) {
                                            Navigator.pop(context, value);
                                          },
                                          fillColor: MaterialStateProperty.resolveWith<Color>(
                                                (Set<MaterialState> states) {
                                              return AppColors.payFinancegreen300Main;
                                            },
                                          ),
                                        ),
                                        const SizedBox(width: kDefaultPadding),
                                        Expanded(
                                          child: Text(
                                            paymentType,
                                            style: AppTextStyles.bodymedium,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: kDefaultPadding),
                              ],
                            );
                          }).toList(),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
      if (installmentType == null) {
        return;
      }
    }

    SystemRepository.preferences.then((sp) {
      BlocProvider.of<CreditCardOptionCubit>(context).validateCC(
        null,
        account.accountProfileId!,
        NumberUtils.doubleToCents(txnAmount),
        selectedPaymentType,
          installmentType == 'Estabelecimento' ? 'SHOP' : null
      );
    });

    bool sending = false,
        sendingProcessPaymentTxn = false,
        paymentProcessed = false,
        serviceProcessedError = false,
        refundProcessed = false,
        sendingProcessRefundPaymentTxn = false,
        pixProcessing = false,
        successQrCodePix = false,
        isMounted = true,
        printing = false;
    Uint8List? imageQrCodePix;

    String? errorMessage, successMessage;
    Installment? installmentSelected;
    CreditCardPaymentOptions? installmentsData;
    String? merchantReferenceCode, paymentId, paymentAmount, txnHeaderId, pixStatus, servicesReceipt;
    double amount = 0.00;
    final platform = const MethodChannel('com.level4.pocketpaypos');

    Future<void> resetFlow({required StateSetter? bottomSheetState}) async {
      bottomSheetState!(() {
        installmentSelected = null;
        installmentsData = null;
        errorMessage = null;
        successMessage = null;
        sending = false;
        printing = false;
      });
    }

    Future<void> resetAmount({required StateSetter? bottomSheetState}) async {
      bottomSheetState!(() {
        installmentSelected = null;
        installmentsData = null;
        errorMessage = null;
        successMessage = null;
        sending = false;
        printing = false;
        amount = 0.00;
        txnAmount = 0.00;
        paymentProcessed = false;
      });
      // resetAmountKeyboard();
    }

    void _setAmountToPay(StateSetter setState) {
      SubTotalInstallments? subTotalInstallment = installmentsData?.subTotalInstallments?.firstWhere(
        (element) => element.times == installmentSelected!.times,
        orElse: () => SubTotalInstallments(times: null, value: null),
      );
      setState(() {
        amount = subTotalInstallment!.value ?? txnAmount;
      });
    }

    /**
     * Processa o envio do registro da transação de estorno na API Pocket
     */
    Future<void> _processSendRefundTxn(
      String txnHeaderId,
      Map<String, dynamic> response,
      Map<String, dynamic> request,
    ) async {
      TransactionResponseDto? resp = await BlocProvider.of<PaymentProcessCubit>(context).processRefundTransaction(
        txnHeaderId,
        response,
        request,
        serialNumber,
      );

      String message = tr('charges_page.label_txn_refund_success');

      if (resp == null) {
        message = tr('label_something_wrong');
      } else if (resp.error) {
        message = tr('charges_page.label_txn_refund_failed');
      } 
      // else if (!resp.error) {
      //   _bottomSheetState!(() {
      //     refundProcessed = true;
      //     installmentSelected = null;
      //     installmentsData = null;
      //     errorMessage = message;
      //     successMessage = null;
      //     sending = false;
      //     printing = false;
      //     sendingProcessRefundPaymentTxn = false;
      //   });
      // }

      _bottomSheetState!(() {
        refundProcessed = true;
        installmentSelected = null;
        installmentsData = null;
        errorMessage = message;
        successMessage = null;
        sending = false;
        printing = false;
        sendingProcessRefundPaymentTxn = false;
      });

      // FunctionsHelper.showModalBottomSheetMessage(
      //   context,
      //   null,
      //   widget: Container(
      //     padding: EdgeInsets.only(top: kDefaultPadding),
      //     height: 100,
      //     child: Text(
      //       message,
      //       style: AppTextStyles.bodylarge.copyWith(color: AppColors.neutrals00Bg),
      //     ),
      //   ),
      // );
    }

    /**
     * Processa o estorno do pagamento com o cartão na máquina
     */
    Future _processRefund() async {
      try {
        _bottomSheetState!(() {
          sending = true;
        });
        Map<String, dynamic> requestData = {
          'value': double.parse(paymentAmount ?? '0').toStringAsFixed(2),
          //double.parse(businessChargeItem.amount ?? '0').toStringAsFixed(2),
          'transactionId': merchantReferenceCode,
          //businessChargeItem.merchantReferenceCode,
          'showReceiptView': true,
          'paymentId': paymentId,
          //businessChargeItem.requestId,
          'setPrintMerchantReceipt': true,
          'setPrintCustomerReceipt': true
        };
        print('_processRefund: $requestData');

        dynamic result = await platform.invokeMethod('startPaymentReversal', requestData);

        _bottomSheetState!(() {
          sending = false;
          sendingProcessRefundPaymentTxn = true;
        });

        print('Result from Java: $result');
        Map<String, dynamic> jsonResult = jsonDecode(result);
        PosRefundResponse refundResponse = PosRefundResponse.fromJson(jsonResult);

        ///Verifica se tem o txnHeaderId para realizar o processamento do estorno. Caso não tenha, a requisição
        ///para realizar o "authorization" do serviço não deu certo
        if (txnHeaderId != null && txnHeaderId != '') {
          await _processSendRefundTxn(txnHeaderId!, jsonResult, requestData);
        } else {
          _bottomSheetState!(() {
            refundProcessed = true;
            installmentSelected = null;
            installmentsData = null;
            errorMessage = tr('charges_page.label_txn_refund_success');
            successMessage = null;
            sending = false;
            sendingProcessRefundPaymentTxn = false;
          });
        }
      } on PlatformException catch (e) {
        print("Failed to Invoke: '${e.message}'.");
        FunctionsHelper.showModalBottomSheetMessage(
            context, e.message ?? 'Ops, ocorreu um erro ao realizar o cancelamento do pagamento.');

        _bottomSheetState!(() {
          sending = false;
          sendingProcessRefundPaymentTxn = false;
        });
      }
    }

    void checkPixStatus(StateSetter setState, String transactionIdBankTransfer) async {
      if (checkPixAttempts < 3 && pixStatus != 'CONFIRMED') {
        await Future.delayed(Duration(seconds: 5));
        PixStatus? pixStatusResponse =
            await BlocProvider.of<PixStatusCubit>(context).processGetPixStatus(requestId: transactionIdBankTransfer);
        setState(() {
          checkPixAttempts++;
        });
        if (pixStatusResponse != null) {
          String? tempPixStatus = pixStatusResponse.responseData?.status ?? null;
          // tempPixStatus = 'PROCESSING';

          switch (tempPixStatus) {
            // case 'CONFIRMED':
            // case 'ERROR':
            //   break;
            case 'PROCESSING':
              checkPixStatus(setState, transactionIdBankTransfer); // Tenta novamente
            case 'INITIATED':
              checkPixStatus(setState, transactionIdBankTransfer); // Tenta novamente
              break;
          }
        }
      }
    }

    /**
     * Processa o registro da transasção de pagamento na API Pocket
     */
    Future<void> _processSendPaymentTxn(
      PosResponse paymentData,
      Map<String, dynamic> requestData,
      StateSetter setState,
    ) async {
      if (installmentSelected == null) return;
      var _paymentFlowState = BlocProvider.of<PaymentFlowCubit>(context);

      PaymentProcessDto dtoTxn = PaymentProcessDto();
      dtoTxn.paymentDetailsDto = PaymentDetailsDto();
      dtoTxn.paymentDetailsDto!.amount = amount;
      dtoTxn.profileId = account.accountProfileId;
      dtoTxn.paymentDetailsDto!.balanceAmount = 0;
      dtoTxn.paymentDetailsDto!.operationAmount = _paymentFlowState.value;
      // dtoTxn.paymentDetailsDto!.installments = paymentData.installments;
      dtoTxn.transactionDetailsDto = TransactionDetailsDto();
      // dtoTxn.paymentDetailsDto!.installments = paymentRequestData != null ? paymentRequestData!.installments ?? 1 : 1;
      dtoTxn.paymentDetailsDto!.installments = requestData['installments'] ?? 1;
      dtoTxn.transactionDetailsDto!.transactionType = 'AuthCapture';
      // dtoTxn.billToDto = BillToDto(
      //   socialSecurityNumber: account.document,
      //   pocketAccountId: account.accountId,
      // );
      dtoTxn.transactionDetailsDto!.methodType = 'TEF';

      setState(() {
        sendingProcessPaymentTxn = true;
      });

      PaymentProcessResponseDto? processTransactionPosData;
      String? defaultErrorMessageByType;
      dtoTxn.merchantDetailsDto = MerchantDetailsDto(account.accountProfileId.toString(), merchantReferenceCode ?? '');
      dtoTxn.txnHeaderId = _paymentFlowState.getOrderTxnHeaderId;

      if (_paymentFlowState.type == PaymentFlowType.transfer) {
        dtoTxn.transactionDetailsDto!.transactionType = 'Authorization';
        dtoTxn.transactionDetailsDto!.transactionType = 'BankTransfer';

        final TransferAccount ta = _paymentFlowState.transferTo;

        String _accountType = 'Conta Corrente';
        String _accountTypeData = ta.bankAccountType ?? '';
        switch (_accountTypeData) {
          case 'SLRY':
            _accountType = 'Conta Salario';
            break;
          case 'SVGS':
            _accountType = 'Conta Poupança';
            break;
        }

        dtoTxn.bankDto = BankDto(
          ispbCode: ta.ispbCode,
          bankId: ta.bank!.id,
          bankCode: ta.bank!.code,
          bankName: ta.bank!.name,
          destinationSocialSecurityNumber: ta.docNumber,
          accountNumber: ta.bankAccountNumber,
          agencyNumber: ta.bankRoutingNumber,
          accountDigit: ta.bankAccountDigit,
          accountType: _accountType,
          pixKey: ta.pixKey,
        );

        dtoTxn.transactionDetailsDto!.destination = ta.name;
        dtoTxn.transactionDetailsDto!.transactionType = 'BankTransfer';

        BankTransfer bankTransferData = BankTransfer();
        bankTransferData.bankId = ta.bank!.id;
        bankTransferData.bankCode = ta.bank!.code;
        bankTransferData.destinationName = ta.name;
        bankTransferData.destinationSocialSecurityNumber = ta.docNumber;
        bankTransferData.agencyNumber = ta.bankRoutingNumber;
        bankTransferData.accountNumber = ta.bankAccountNumber;
        bankTransferData.accountDigit = ta.bankAccountDigit;
        bankTransferData.accountType = _accountType;
        bankTransferData.pixKey = ta.pixKey;
        bankTransferData.bankName = ta.bank!.name;
        bankTransferData.pixMessage = ta.pixMessage;
        dtoTxn.bankTransfer = bankTransferData;

        processTransactionPosData = await BlocProvider.of<PaymentProcessCubit>(context).process(
          _paymentFlowState,
          dtoTxn,
          paymentData,
          requestData,
          selectedPaymentType,
          installmentsData?.profileIdProcess ?? '',
          serialNumber,
        );

        defaultErrorMessageByType = 'Ocorreu um erro no processamento do pix, infelizmente será necessário estornar o valor.';

        if (processTransactionPosData != null) {
          pixProcessing = processTransactionPosData.decision == 'ACCEPT';
          String? transactionIdBankTransfer = processTransactionPosData.transactionIdBankTransfer ?? null;

          // if (transactionIdBankTransfer != null){
          // Future.delayed(Duration(seconds: 10)).then((value) async {
          //   await BlocProvider.of<PixStatusCubit>(context).processGetPixStatus(requestId: transactionIdBankTransfer);
          //   setState(() {
          //     checkPixAttempts++;
          //   });
          // });
          // }
          if (transactionIdBankTransfer != null) {
            checkPixAttempts = 0; // Certifique-se de inicializar a variável
            checkPixStatus(setState, transactionIdBankTransfer); // Inicia a verificação
          }
        }
      } else if (_paymentFlowState.type == PaymentFlowType.recharge_phone) {
        ///monta o model dos dados de recarga de celular
        MobileRecharge mobileRechargeData = MobileRecharge();
        dtoTxn.billToDto = BillToDto(
            // socialSecurityNumber: account.document,
            // pocketAccountId: account.accountId,
            phoneNumber: StringUtils.onlyNumbers(_paymentFlowState.state.phoneNumber),
            carrierCode: _paymentFlowState.state.phoneProvider!.carrierCode);
        String phoneData = StringUtils.onlyNumbers(_paymentFlowState.state.phoneNumber);
        mobileRechargeData.areaCode = phoneData.substring(0, 2);
        mobileRechargeData.phoneNumber = phoneData.substring(2);
        mobileRechargeData.carrierCode = _paymentFlowState.state.phoneProvider!.carrierCode;
        mobileRechargeData.carrierName = _paymentFlowState.state.phoneProvider!.name;
        dtoTxn.mobileRecharge = mobileRechargeData;
        dtoTxn.transactionDetailsDto!.destination = 'Recarga ${_paymentFlowState.state.phoneProvider!.name}';
        dtoTxn.transactionDetailsDto!.transactionType = 'MobileRecharge';

        processTransactionPosData = await BlocProvider.of<PaymentProcessCubit>(context).process(
          _paymentFlowState,
          dtoTxn,
          paymentData,
          requestData,
          selectedPaymentType,
          installmentsData?.profileIdProcess ?? '',
          serialNumber,
        );
        defaultErrorMessageByType = 'Ocorreu um erro no processamento da recarga, infelizmente será necessário estornar o valor.';
      } else if (_paymentFlowState.type == PaymentFlowType.bill) {
        dtoTxn.transactionDetailsDto!.billCode = _paymentFlowState.state.barCodeResult!.rawCode;
        dtoTxn.transactionDetailsDto!.destination = _paymentFlowState.state.billInformation!.assignor;
        dtoTxn.transactionDetailsDto!.transactionType = 'BillPayment';
        dtoTxn.transactionDetailsDto!.operationType = 'BillPayment';
        dtoTxn.billPaymentScheduledDate = _paymentFlowState.state.billInformation!.scheduledDate ?? null;
        dtoTxn.billToDto = BillToDto(
          socialSecurityNumber: _paymentFlowState.billPaymentSocialSecurityNumber,
        );
        processTransactionPosData = await BlocProvider.of<PaymentProcessCubit>(context).process(
          _paymentFlowState,
          dtoTxn,
          paymentData,
          requestData,
          selectedPaymentType,
          installmentsData?.profileIdProcess ?? '',
          serialNumber,
        );
        defaultErrorMessageByType =
            'Ocorreu um erro no processamento da pagamento, infelizmente será necessário estornar o valor.';
      } else if (_paymentFlowState.type == PaymentFlowType.vehicle_debts) {
        dtoTxn.transactionDetailsDto!.transactionType = 'AuthCapture';
        dtoTxn.transactionDetailsDto!.operationType = 'VehicleDebit';
        final List<dynamic> products = [];
        int instalmentState = installmentSelected?.times ?? 1; //_paymentFlowState.installment!.times ?? 1;
        double taxAmount =
            _paymentFlowState.creditCardPaymentOptions!.installmentsPercentValue![instalmentState - 1].value ?? 0.0;
        _paymentFlowState.state.vehicleDebts!.asMap().forEach((index, p) {
          products.add({
            "productId": p.id,
            "productName": '${tr('page_vehicle_debts.label_debt_type_${describeEnum(p.type!)}')} - ${p.title}',
            "unitPrice": p.amount!,
            "taxAmount": taxAmount,
            "quantity": 1
          });
        });
        dtoTxn.products = products;

        TransactionResponseDto? transactionResponseDto =
            await BlocProvider.of<PaymentProcessCubit>(context).processTransactionPos(
          dtoTxn,
          paymentData,
          account,
          '',
          requestData,
          selectedPaymentType,
          _paymentFlowState,
          installmentsData?.profileIdProcess ?? '',
          serialNumber,
        );

        Map<String, dynamic> json = {};
        json['decision'] = transactionResponseDto?.decision ?? 'REJECT';
        json['reasonMessage'] = transactionResponseDto?.reasonMessage ?? '';
        json['errorMessage'] = transactionResponseDto?.reasonMessage ?? '';
        json['requestId'] = transactionResponseDto?.requestId ?? '';
        if (transactionResponseDto?.receiptInformation != null)
          json['receiptInformation'] = ReceiptInformation().toJson(transactionResponseDto?.receiptInformation ?? {});
        processTransactionPosData = PaymentProcessResponseDto().inflateFromJson(json);

        defaultErrorMessageByType =
            'Ocorreu um erro no processamento do débito veicular, infelizmente será necessário estornar o valor.';
      } else {
        // TransactionResponseDto? processTransactionPosData = await BlocProvider.of<PaymentProcessCubit>(context).processTransactionPos(
        //   dtoTxn,
        //   paymentData,
        //   account,
        //   paymentData.nsuTerminal,
        //   requestData,
        // );
        // processTransactionPosData = await BlocProvider.of<PaymentProcessCubit>(context).process(_paymentFlowState.type!, dtoTxn);
      }

      setState(() {
        sendingProcessPaymentTxn = false;
      });

      if (processTransactionPosData == null) {
      } else {
        bool error = true; //processTransactionPosData.decision != 'ACCEPT';

        ///forçar erro
        // error = true;
        // if (_paymentFlowState.type == PaymentFlowType.recharge_phone) {
        //   processTransactionPosData.errorMessage =
        //       'Ocorreu um erro no processamento da recarga, infelizmente será necessário estornar o valor.';
        // }

        if (error) {
          // final Map<String, dynamic> transactionData = {
          //   "Errors": false,
          //   "ErrorMessage": "Erro fake",
          //   "Data" : [{
          //     "txnHeaderId": processTransactionPosData.requestId,
          //     "payment_type": null,
          //     "terminal_pinpad": null,
          //     "event_id": null,
          //     "row_id": null,
          //     "merchantreferencecode": processTransactionPosData.merchantReferenceCode,
          //     "requestid": paymentData.paymentId,
          //     "timeAgo": "há 32 segundos",
          //     "dtCreated": "27/11/2024 18:07:25",
          //     "dtUpdated": "27/11/2024 18:07:31",
          //     "dtUpdated2": "2024-11-27 21:07:31",
          //     "status": "Captured",
          //     "card_lastfour": "1234",
          //     "card_type": "001",
          //     "payeerProfileId": "L4645XB",
          //     "totalAmount": "105.00",
          //     "amount": paymentData.value.toString(),
          //     "userAccount": "Aguinaldo Aranda",
          //     "userContactName": null,
          //     "userAccountId": null,
          //     "userPhone": "11930425522",
          //     "userMail": "",
          //     "currencyCode": "BRL",
          //     "currencySymbol": "R\$",
          //     "ticketNumber": "TICKET9876",
          //     "paymentLink": "https://portalhom.mypocketpay.com/new/payments/L4D7JBL97c",
          //     "cardBrand": "Visa",
          //     "products": []
          //   }]
          //
          // };

          // final BusinessCharges businessChargeItem = BusinessCharges.fromJson(transactionData);
          // await _processRefund(businessChargeItem.dataContent![0]);
          processTransactionPosData.errorMessage = defaultErrorMessageByType;
        }

        if (_bottomSheetState != null) {
          _bottomSheetState!(() {
            txnHeaderId = processTransactionPosData?.requestId;
            servicesReceipt = processTransactionPosData?.receiptInformation?.receiptFormatted;
            paymentId = paymentData.paymentId;
            paymentAmount = paymentData.value.toString();
            serviceProcessedError = error;
            successMessage = error != true
                ? (processTransactionPosData?.errorMessage ?? processTransactionPosData?.reasonMessage) ??
                    tr('label_success_message')
                : null;
            errorMessage = error != false
                ? (processTransactionPosData?.errorMessage ?? processTransactionPosData?.reasonMessage) ??
                    tr('label_something_wrong')
                : null;
            sending = false;
          });
        }
      }
    }

    String buildSuccessMessage(String operationType) {
      switch (operationType) {
        case 'BillPayment':
          return 'Pagamento do boleto realizado com sucesso!';
        case 'MobileRecharge':
          return 'Recarga de celular realizada com sucesso!';
        case 'VehicleDebit':
          return 'Pagamento de débito veicular realizado com sucesso!';
        default:
          return 'Pagamento do pix confirmado com sucesso!';
      }
    }

    Future<void> fetchTransactionStatus(
      String txnHeaderId,
      StateSetter setState,
      String operationType,
    ) async {
      List<int> delays = [15, 10, 10, 10]; // Intervalos em segundos
      for (int delay in delays) {
        await Future.delayed(Duration(seconds: delay));
        if (isMounted == false) {
          print("Widget desmontado. Cancelando processamento.");

          ///Chama a rotina para fazer o refund do pix para o caso do usuário ter feito antes da tela ser fechada
          BlocProvider.of<PaymentProcessCubit>(context).processSendPixRefund(
            txnHeaderId,
            serialNumber,
          );
          return;
        }
        TransactionStatus? processTransactionStatus =
            await BlocProvider.of<PaymentProcessCubit>(context).processGetTransactionStatus(txnHeaderId);
        print(
            "Tentativa às ${DateTime.now()} com intervalo de $delay segundos - Status: ${processTransactionStatus?.receiptData?.status}");

        if (processTransactionStatus?.receiptData?.status == 'Captured') {
          setState(() {
            successQrCodePix = false;
            // successMessage = 'Pagamento do pix confirmado com sucesso!';
            successMessage = buildSuccessMessage(operationType);
            servicesReceipt = processTransactionStatus?.receiptData?.receiptFormatted ?? '';

          });
          return;
        }
      }
      if (isMounted == true) {
        setState(() {
          successMessage = null;
          successQrCodePix = false;
          imageQrCodePix = null;
          errorMessage = 'O pagamento não foi confirmado. Por favor, tente novamente ou entre em contato com o suporte.';
        });
      }

      ///Chama a rotina para fazer o refund do pix para o caso do usuário ter feito antes do tempo de espera acabar.
      Future.delayed(Duration(milliseconds: 500)).then((value) {
        BlocProvider.of<PaymentProcessCubit>(context).processSendPixRefund(
          txnHeaderId,
          serialNumber,
        );
      });

      print("Transação não completada após 3 tentativas.");
    }

    PaymentProcessDto createRequestServices(PaymentFlowCubit _paymentFlowState, int installments) {
      PaymentProcessDto dtoTxn = PaymentProcessDto();
      dtoTxn.paymentDetailsDto = PaymentDetailsDto();
      dtoTxn.paymentDetailsDto!.amount = amount;
      dtoTxn.profileId = account.accountProfileId;
      dtoTxn.paymentDetailsDto!.balanceAmount = 0;
      dtoTxn.paymentDetailsDto!.operationAmount = _paymentFlowState.value;
      dtoTxn.transactionDetailsDto = TransactionDetailsDto();
      // dtoTxn.paymentDetailsDto!.installments = paymentRequestData != null ? paymentRequestData!.installments ?? 1 : 1;
      dtoTxn.paymentDetailsDto!.installments = installments;
      // dtoTxn.transactionDetailsDto!.transactionType = 'AuthCapture';

      dtoTxn.billToDto = BillToDto(
        socialSecurityNumber: _paymentFlowState.billPaymentSocialSecurityNumber,
        // pocketAccountId: account.accountId,
      );
      dtoTxn.transactionDetailsDto!.methodType = 'TEF';

      PaymentProcessResponseDto? processTransactionPosData;
      String? defaultErrorMessageByType;
      dtoTxn.merchantDetailsDto = MerchantDetailsDto(account.accountProfileId.toString(), merchantReferenceCode ?? '');
      dtoTxn.txnHeaderId = _paymentFlowState.getOrderTxnHeaderId;

      if (_paymentFlowState.type == PaymentFlowType.transfer) {
        dtoTxn.transactionDetailsDto!.transactionType = 'Authorization';
        dtoTxn.transactionDetailsDto!.transactionType = 'BankTransfer';

        final TransferAccount ta = _paymentFlowState.transferTo;

        String _accountType = 'Conta Corrente';
        String _accountTypeData = ta.bankAccountType ?? '';
        switch (_accountTypeData) {
          case 'SLRY':
            _accountType = 'Conta Salario';
            break;
          case 'SVGS':
            _accountType = 'Conta Poupança';
            break;
        }

        dtoTxn.bankDto = BankDto(
          ispbCode: ta.ispbCode,
          bankId: ta.bank!.id,
          bankCode: ta.bank!.code,
          bankName: ta.bank!.name,
          destinationSocialSecurityNumber: ta.docNumber,
          accountNumber: ta.bankAccountNumber,
          agencyNumber: ta.bankRoutingNumber,
          accountDigit: ta.bankAccountDigit,
          accountType: _accountType,
          pixKey: ta.pixKey,
        );

        dtoTxn.transactionDetailsDto!.destination = ta.name;
        dtoTxn.transactionDetailsDto!.transactionType = 'BankTransfer';

        BankTransfer bankTransferData = BankTransfer();
        bankTransferData.bankId = ta.bank!.id;
        bankTransferData.bankCode = ta.bank!.code;
        bankTransferData.destinationName = ta.name;
        bankTransferData.destinationSocialSecurityNumber = ta.docNumber;
        bankTransferData.agencyNumber = ta.bankRoutingNumber;
        bankTransferData.accountNumber = ta.bankAccountNumber;
        bankTransferData.accountDigit = ta.bankAccountDigit;
        bankTransferData.accountType = _accountType;
        bankTransferData.pixKey = ta.pixKey;
        bankTransferData.bankName = ta.bank!.name;
        bankTransferData.pixMessage = ta.pixMessage;
        dtoTxn.bankTransfer = bankTransferData;
      } else if (_paymentFlowState.type == PaymentFlowType.recharge_phone) {
        ///monta o model dos dados de recarga de celular
        MobileRecharge mobileRechargeData = MobileRecharge();
        dtoTxn.billToDto = BillToDto(
            // socialSecurityNumber: account.document,
            // pocketAccountId: account.accountId,
            phoneNumber: StringUtils.onlyNumbers(_paymentFlowState.state.phoneNumber),
            carrierCode: _paymentFlowState.state.phoneProvider!.carrierCode);
        String phoneData = StringUtils.onlyNumbers(_paymentFlowState.state.phoneNumber);
        mobileRechargeData.areaCode = phoneData.substring(0, 2);
        mobileRechargeData.phoneNumber = phoneData.substring(2);
        mobileRechargeData.carrierCode = _paymentFlowState.state.phoneProvider!.carrierCode;
        mobileRechargeData.carrierName = _paymentFlowState.state.phoneProvider!.name;
        dtoTxn.mobileRecharge = mobileRechargeData;
        dtoTxn.transactionDetailsDto!.destination = 'Recarga ${_paymentFlowState.state.phoneProvider!.name}';
        dtoTxn.transactionDetailsDto!.transactionType = 'Authorization';
        dtoTxn.transactionDetailsDto!.operationType = 'MobileRecharge';
      } else if (_paymentFlowState.type == PaymentFlowType.bill) {
        dtoTxn.transactionDetailsDto!.billCode = _paymentFlowState.state.barCodeResult!.rawCode;
        dtoTxn.transactionDetailsDto!.destination = _paymentFlowState.state.billInformation!.assignor;
        dtoTxn.transactionDetailsDto!.transactionType = 'Authorization';
        dtoTxn.transactionDetailsDto!.operationType = 'BillPayment';
        // dtoTxn.billToDto?.socialSecurityNumber = '26369129836';
        // dtoTxn.billPaymentScheduledDate = _paymentFlowState.state.billInformation!.scheduledDate ?? null;
      } else if (_paymentFlowState.type == PaymentFlowType.vehicle_debts) {
        dtoTxn.transactionDetailsDto!.transactionType = 'Authorization';
        dtoTxn.transactionDetailsDto!.operationType = 'VehicleDebit';
        final List<dynamic> products = [];
        int instalmentState = installmentSelected?.times ?? 1; //_paymentFlowState.installment!.times ?? 1;
        double taxAmount =
            _paymentFlowState.creditCardPaymentOptions!.installmentsPercentValue![instalmentState - 1].value ?? 0.0;
        _paymentFlowState.state.vehicleDebts!.asMap().forEach((index, p) {
          products.add({
            "productId": p.id,
            "productName": '${tr('page_vehicle_debts.label_debt_type_${describeEnum(p.type!)}')} - ${p.title}',
            "unitPrice": p.amount!,
            "taxAmount": taxAmount,
            "quantity": 1
          });
        });
        dtoTxn.products = products;
      } else {
        // TransactionResponseDto? processTransactionPosData = await BlocProvider.of<PaymentProcessCubit>(context).processTransactionPos(
        //   dtoTxn,
        //   paymentData,
        //   account,
        //   paymentData.nsuTerminal,
        //   requestData,
        // );
        // processTransactionPosData = await BlocProvider.of<PaymentProcessCubit>(context).process(_paymentFlowState.type!, dtoTxn);
      }

      return dtoTxn;
    }

    /**
     * Processa o pagamento com o cartão na máquina
     */
    Future _processPayment(String paymentType, StateSetter setState) async {
      if (installmentSelected == null) return;

      // if (_bottomSheetState != null) {
      //   _bottomSheetState!(() {
      //     sending = true;
      //   });
      // }

      setState(() {
        sending = true;
      });
      merchantReferenceCode = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();

      try {
        dynamic result;
        Map<String, dynamic> requestData = {};
        if (paymentType == 'PIX') {
          // PaymentProcessDto dtoTxn = PaymentProcessDto();
          PaymentFlowCubit _paymentFlowState = BlocProvider.of<PaymentFlowCubit>(context);

          PaymentProcessDto dtoTxn = createRequestServices(_paymentFlowState, 1);

          TransactionResponseDto? processTransactionResponse =
              await BlocProvider.of<PaymentProcessCubit>(context).processTransaction(
            _paymentFlowState.type!,
            dtoTxn,
            PaymentType.pix,
            installmentsData?.profileIdProcess ?? '',
            serialNumber,
          );

          if (processTransactionResponse == null || processTransactionResponse.decision != 'ACCEPT') {
            String? _errorMessage = processTransactionResponse?.reasonMessage ??
                'Ops, ocorreu um erro na geração do pix.\nTente novamente, caso o erro persista, entre em contato com o suporte por favor.';

            setState(() {
              successMessage = null;
              errorMessage = _errorMessage;
              successQrCodePix = false;
              imageQrCodePix = null;
            });
          } else {
            final sanitizedBase64 = (processTransactionResponse.qrCode ?? '').replaceFirst("data:image/png;base64,", "");
            Uint8List _imageQrCode = base64Decode(sanitizedBase64);

            setState(() {
              successQrCodePix = true;
              imageQrCodePix = _imageQrCode;
              successMessage = processTransactionResponse.reasonMessage ?? '';
              isMounted = true;
              paymentProcessed = true;
            });

            //consulta o status da txn
            String txnHeaderId = processTransactionResponse.requestId ?? '';
            if (txnHeaderId != '') {
              await fetchTransactionStatus(
                txnHeaderId,
                setState,
                dtoTxn.transactionDetailsDto?.operationType ?? '',
              );
            }
          }
        } else {
          requestData = {
            'value': amount.toString(), //(amount * 100).toString(),
            'transactionId': merchantReferenceCode,
            'showReceiptView': true,
            'paymentTypeArrayString': [paymentType],
            // 'paymentTypeArrayString': ['CREDIT', 'DEBIT'],
            'installments': installmentSelected!.times,
            'confirmPayment': true
          };
          print('_processPayment: $requestData');

          // if (!cieloConectaSimulated){
          //   dynamic result = await platform.invokeMethod('startPayment', requestData);
          // } else {
          result = await platform.invokeMethod('startPayment', requestData);
          //  result = '';
          // }

          setState(() {
            // errorMessage = result;
            sending = false;
            merchantReferenceCode = merchantReferenceCode;
          });

          // print('Result from Java: $result');
          Map<String, dynamic> jsonMap = jsonDecode(result);
          PosResponse paymentResponse = PosResponse.fromJson(jsonMap);

          // //retorno fake, comentar as linhas acima
          // PosResponse paymentResponse = PosResponse(
          //   batchNumber: "123456",
          //   cardHolderName: "John Doe",
          //   lastTrx: true,
          //   nsuTerminal: "NSU12345",
          //   ticketNumber: "TICKET9876",
          //   acquirer: "Acquirer X",
          //   acquirerAuthorizationNumber: "AUTH7890",
          //   acquirerId: "ACQ123",
          //   acquirerNsu: "NSU6789",
          //   acquirerResponseCode: "00",
          //   acquirerResponseDate: DateTime.now().toUtc().toIso8601String().split('.').first + 'Z',
          //   captureType: "EMV",
          //   card: CardInfo(
          //     bin: "123456",
          //     brand: "Visa",
          //     panLast4Digits: "1234",
          //   ),
          //   installments: installmentSelected!.times!,
          //   paymentDate: DateTime.now().toUtc().toIso8601String().split('.').first + 'Z',
          //   paymentId: "PAYID9876",
          //   paymentStatus: PaymentStatus.CONFIRMED,
          //   paymentType: "Credit",
          //   receipt: ReceiptResponsePos(
          //     clientVia: "Client Receipt Content",
          //     merchantVia: "Merchant Receipt Content",
          //   ),
          //   value: amount,
          // );

          print('Result from Java -> flutter: ${paymentResponse.cardHolderName}');

          if (paymentResponse.paymentStatus == PaymentStatus.CONFIRMED) {
            _bottomSheetState!(() {
              paymentProcessed = true;
            });
            await _processSendPaymentTxn(paymentResponse, requestData, setState);
          } else {
            _bottomSheetState!(() {
              paymentProcessed = true;
              errorMessage =
                  "Ops, ocorreu um erro no processamento do seu pagamento.\nTente novamente, caso o erro persista, entre em contato com o suporte por favor.";
            });
          }
        }
      } on PlatformException catch (e) {
        print("Failed to Invoke: '${e.message}'.");
        String? _errorCode = e.code;
        String? _errorMessage = e.message;

        if (_errorCode == "99" || _errorMessage == null || _errorMessage == '') {
          _errorMessage =
              "Ops, ocorreu um erro no processamento do seu pagamento.\nTente novamente, caso o erro persista, entre em contato com o suporte por favor.";
        }

        setState(() {
          errorMessage = _errorMessage;
          sending = false;
        });
      }
    }

    /**
     * Exibe o fluxo do pagamento
     */
    await showModalBottomSheet(
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      context: context,
      builder: (context) {
        return BlocListener<PixStatusCubit, PixStatusState>(
          listener: (context, state) {
            String? _pixStatus;
            if (state.isType(PixStatusStates.error)) {
              // _pixStatus = 'ERROR';
              _bottomSheetState!(() {
                pixStatus = 'ERROR';
                pixProcessing = false;
                errorMessage = 'Ocorreu um erro no processamento do pix, infelizmente será necessário estornar o valor.';
                successMessage = null;
              });
            } else if (state.isType(PixStatusStates.loaded)) {
              final pixStatusResponse = state.payload as PixStatus;
              _pixStatus = pixStatusResponse.responseData?.status ?? null;
              String? tempErrorMessage, tempSuccessMessage;
              bool tempPixProcessing = true, tempPixError = false;

              switch (_pixStatus) {
                case 'CONFIRMED':
                  tempSuccessMessage = 'Pix realizado com sucesso';
                  tempPixProcessing = false;
                  break;
                case 'PROCESSING':
                case 'INITIATED':
                  if (checkPixAttempts >= 3) {
                    tempPixProcessing = false;
                  }
                  break;
                case 'ERROR':
                  tempErrorMessage = 'Ocorreu um erro no processamento do pix, infelizmente será necessário estornar o valor.';
                  tempPixProcessing = false;
                  tempPixError = true;
                  break;
              }

              _bottomSheetState!(() {
                pixStatus = _pixStatus;
                pixProcessing = tempPixProcessing;
                errorMessage = tempErrorMessage;
                successMessage = tempSuccessMessage;
                serviceProcessedError = tempPixError;
              });
            }
          },
          child: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              _bottomSheetState = setState;

              return FractionallySizedBox(
                // heightFactor: 0.8,
                heightFactor: successQrCodePix && imageQrCodePix != null && imageQrCodePix != '' ? 0.9 : 0.8,
                child: WillPopScope(
                  onWillPop: () async {
                    // Condição para permitir ou impedir o fechamento
                    if (!serviceProcessedError) {
                      return true; // Permite o fechamento
                    } else {
                      return false; // Impede o fechamento
                    }
                  },
                  child: Scaffold(
                    backgroundColor: Colors.transparent,
                    appBar: AppBar(
                      backgroundColor: Colors.transparent,
                      automaticallyImplyLeading: false,
                      elevation: 0,
                      title: _buildProcessTitle(
                        installmentSelected: installmentSelected,
                        sending: sending,
                        sendingProcessPaymentTxn: sendingProcessPaymentTxn,
                        successMessage: successMessage,
                        errorMessage: errorMessage,
                        selectedPaymentType: selectedPaymentType,
                        pixProcessing: pixProcessing,
                        checkPixAttempts: checkPixAttempts,
                        successQrCodePix: successQrCodePix,
                      ),
                      actions: [
                        if (!serviceProcessedError || sendingProcessRefundPaymentTxn)
                          IconButton(
                            onPressed: () async {
                              if (!paymentProcessed) {
                                // await resetFlow(bottomSheetState: _bottomSheetState);
                                await resetFlow(bottomSheetState: setState);
                                Navigator.pop(context);
                              } else {
                                // Navigator.pop(context);
                                await resetAmount(bottomSheetState: setState);
                                Navigator.push(
                                    context, MaterialPageRoute(builder: (_) => HomeScreen(account: account, pageIndex: 0)));
                              }
                            },
                            icon: Icon(
                              Icons.close,
                              color: AppColors.neutrals00Bg,
                            ),
                          ),
                      ],
                    ),
                    body: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: kDefaultPaddingLeftRight),
                        child: BlocConsumer<CreditCardOptionCubit, CreditCardOptionState>(
                          listener: (context, state) async {
                            if (state.isType(CreditCardOptionStates.loaded)) {
                              CreditCardPaymentOptions _installmentsData = state.payload;
                              List<Installment>? installments = _installmentsData.installments ?? [];
                              if (selectedPaymentType == 'DEBIT' || selectedPaymentType == 'PIX') {
                                //               SubTotalInstallments? subTotalInstallment = _installmentsData.subTotalInstallments?.firstWhere(
                                //                     (element) => element.times == installmentSelected!.times,
                                //                 orElse: () => SubTotalInstallments(times: null, value: null),
                                //               );
                                // print(subTotalInstallment);

                                setState(() {
                                  // amount = installments[0].value ?? txnAmount;
                                  installmentSelected = installments[0];
                                  installmentsData = _installmentsData;
                                });
                                _setAmountToPay(setState);
                              }
                            }
                          },
                          builder: (context, state) {
                            if (state.isType(CreditCardOptionStates.loading)) {
                              return const CircularProgressIndicator(); // Substitua pelo shimmer original
                            }

                            if (state.isType(CreditCardOptionStates.loaded)) {
                              CreditCardPaymentOptions _installmentsData = state.payload;
                              List<Installment>? installments = _installmentsData.installments ?? [];

                              BlocProvider.of<PaymentFlowCubit>(context).setCreditCardPaymentOptions(_installmentsData);

                              ///Conteúdo processando txn
                              if (sendingProcessPaymentTxn) {
                                return Column(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    const SizedBox(
                                      height: kDefaultPadding,
                                    ),
                                    JumpingDots(
                                      color: AppColors.payFinancegreen300Main,
                                      verticalOffset: -10,
                                    ),
                                    const SizedBox(
                                      height: kDefaultPadding,
                                    ),
                                    Text(
                                      'Processando pagamento...',
                                      style: TextStyle(color: kPrimaryTextColor, fontSize: 16),
                                    ),
                                    const SizedBox(
                                      height: kDefaultPadding,
                                    ),
                                  ],
                                );
                              }

                              ///Conteúdo aguardando confirmação pix
                              if (pixProcessing) {
                                return Column(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    const SizedBox(
                                      height: kDefaultPadding,
                                    ),
                                    // const Icon(
                                    //   Icons.more_horiz,
                                    //   color: kPrimaryColor,
                                    //   size: 62,
                                    // ),
                                    JumpingDots(
                                      color: AppColors.payFinancegreen300Main,
                                      verticalOffset: -10,
                                    ),
                                    const SizedBox(
                                      height: kDefaultPadding,
                                    ),
                                    Text(
                                      'Processando transferência, aguarde...',
                                      style: TextStyle(color: kPrimaryTextColor, fontSize: 16),
                                    ),
                                    const SizedBox(
                                      height: kDefaultPadding,
                                    ),
                                  ],
                                );
                              }

                              ///procesos de transf pix, tentativas excedidas
                              if (!pixProcessing && checkPixAttempts >= 3) {
                                return Column(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    const SizedBox(
                                      height: kDefaultPadding,
                                    ),
                                    const Icon(
                                      Icons.warning_amber,
                                      color: kPrimaryColor,
                                      size: 62,
                                    ),
                                    const SizedBox(
                                      height: kDefaultPadding,
                                    ),
                                    Text(
                                      'O tempo de resposta do pix está demorando mais que o esperado, você pode consultar o status na lista de cobranças realizadas.',
                                      style: TextStyle(color: kPrimaryTextColor, fontSize: 16),
                                    ),
                                    const SizedBox(
                                      height: kDefaultPadding,
                                    ),
                                    TextButton.icon(
                                      onPressed: () {
                                        Navigator.pushReplacement(
                                            context,
                                            MaterialPageRoute(
                                                builder: (_) => PosListScreen(
                                                      account: account,
                                                      returnTo: 'home',
                                                    )));
                                      },
                                      icon: Icon(Icons.list),
                                      label: Text('Acessar agora'),
                                    ),
                                    const SizedBox(
                                      height: kDefaultPadding,
                                    ),
                                  ],
                                );
                              }

                              ///Conteúdo pix qr code sucesso
                              if (successQrCodePix && imageQrCodePix != null && imageQrCodePix != '') {
                                return Column(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    const SizedBox(
                                      height: kDefaultPadding,
                                    ),
                                    const Icon(
                                      Icons.check_circle_rounded,
                                      color: kPrimaryColor,
                                      size: 48,
                                    ),
                                    const SizedBox(
                                      height: kDefaultPadding,
                                    ),
                                    Text(
                                      'Utilize o aplicativo do banco de sua preferência para ler o Qrcode e realizar o pagamento.',
                                      style: TextStyle(color: kPrimaryTextColor, fontSize: 14),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(
                                      height: kDefaultPadding / 2,
                                    ),
                                    Container(
                                      decoration: BoxDecoration(
                                        color: kPrimaryTextColor,
                                        borderRadius: BorderRadius.circular(8.0),
                                      ),
                                      height: 220,
                                      padding: const EdgeInsets.all(5.0),
                                      child: Image.memory(
                                        imageQrCodePix!,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                    const SizedBox(
                                      height: kDefaultPadding,
                                    ),
                                    JumpingDots(
                                      color: AppColors.payFinancegreen300Main,
                                      verticalOffset: -10,
                                    ),
                                    const SizedBox(
                                      height: kDefaultPadding / 2,
                                    ),
                                    Container(
                                      height: 30,
                                      child: DefaultTextStyle(
                                        style: const TextStyle(
                                          fontSize: 14.0,
                                        ),
                                        child: AnimatedTextKit(
                                          isRepeatingAnimation: false,
                                          repeatForever: false,
                                          animatedTexts: List.generate(8, (index) {
                                            return FadeAnimatedText(
                                              'Aguardando confirmação do pagamento...',
                                              duration: Duration(seconds: 4),
                                            );
                                          }),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(
                                      height: kDefaultPadding,
                                    ),
                                    Container(
                                      height: 56,
                                      child: RawMaterialButton(
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        fillColor: kBackgroundColor,
                                        padding: EdgeInsets.symmetric(horizontal: kDefaultPadding),
                                        onPressed: () async {
                                          // if (mounted) await resetFlow();
                                          await resetFlow(bottomSheetState: setState);
                                          Navigator.pop(context);
                                        },
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.center,
                                          mainAxisSize: MainAxisSize.max,
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              'Cancelar',
                                              style: AppTextStyles.button.copyWith(color: AppColors.neutrals00Bg),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              }

                              ///Conteúdo txn sucesso
                              if (successMessage != null) {
                                return Column(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    const SizedBox(
                                      height: kDefaultPadding,
                                    ),
                                    const Icon(
                                      Icons.check_circle_rounded,
                                      color: kPrimaryColor,
                                      size: 62,
                                    ),
                                    const SizedBox(
                                      height: kDefaultPadding,
                                    ),
                                    Text(
                                      successMessage.toString(),
                                      style: TextStyle(color: kPrimaryTextColor, fontSize: 16),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(
                                      height: kDefaultPadding,
                                    ),
                                    Container(
                                      height: 56,
                                      child: RawMaterialButton(
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        fillColor: kBackgroundColor,
                                        padding: EdgeInsets.symmetric(horizontal: kDefaultPadding),
                                        onPressed: () async {
                                          await resetAmount(bottomSheetState: _bottomSheetState);
                                          // Navigator.pop(context);
                                          Navigator.push(context,
                                              MaterialPageRoute(builder: (_) => HomeScreen(account: account, pageIndex: 0)));
                                        },
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.center,
                                          mainAxisSize: MainAxisSize.max,
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            const SizedBox(
                                              width: 5,
                                            ),
                                            Text(tr('label_close'),
                                                style: AppTextStyles.button.copyWith(color: AppColors.neutrals00Bg,),),
                                          ],
                                        ),
                                      ),
                                    ),
                                    if (_paymentFlowState.type == PaymentFlowType.recharge_phone ||
                                        _paymentFlowState.type == PaymentFlowType.bill ||
                                        _paymentFlowState.type == PaymentFlowType.transfer ||
                                        _paymentFlowState.type == PaymentFlowType.vehicle_debts)
                                      Container(
                                        margin: EdgeInsets.only(
                                          top: 20,
                                        ),
                                        height: 56,
                                        child: RawMaterialButton(
                                          elevation: 0,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          fillColor: kPrimaryColor,
                                          padding: EdgeInsets.symmetric(horizontal: kDefaultPadding),
                                          onPressed: () async {
                                            if (printing == true) return;
                                            setState(() {
                                              printing = true;
                                            });

                                            await FunctionsHelper.customPrint(
                                              context,
                                              servicesReceipt ?? '',
                                              removeFirstLine: true,
                                            );
                                            
                                            setState(() {
                                              printing = false;
                                            });
                                          },
                                          child: Row(
                                            crossAxisAlignment: CrossAxisAlignment.center,
                                            mainAxisSize: MainAxisSize.max,
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              if (printing == true)
                                                const SizedBox(
                                                    width: 20,
                                                    height: 20,
                                                    child: CircularProgressIndicator(
                                                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.neutrals900),
                                                    )),
                                              if (printing == false)
                                                const SizedBox(
                                                  width: 5,
                                                ),
                                              if (printing == false)
                                                Text(
                                                  'Comprovante',
                                                  style: AppTextStyles.button.copyWith(
                                                    color: AppColors.neutrals900,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                  ],
                                );
                              }

                              ///conteúdo processando refund
                              if (sendingProcessRefundPaymentTxn) {
                                return Column(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    const SizedBox(
                                      height: kDefaultPadding,
                                    ),
                                    // const Icon(
                                    //   Icons.more_horiz,
                                    //   color: kPrimaryColor,
                                    //   size: 62,
                                    // ),
                                    JumpingDots(
                                      color: AppColors.payFinancegreen300Main,
                                      verticalOffset: -10,
                                    ),
                                    const SizedBox(
                                      height: kDefaultPadding,
                                    ),
                                    Text(
                                      'Processando estorno, aguarde...',
                                      style: TextStyle(color: kPrimaryTextColor, fontSize: 16),
                                    ),
                                    const SizedBox(
                                      height: kDefaultPadding,
                                    ),
                                  ],
                                );
                              }

                              ///Conteúdo txn erro
                              if (errorMessage != null) {
                                return Column(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.info,
                                      color: serviceProcessedError && refundProcessed ? kPrimaryColor : kTextColorError,
                                      size: 62,
                                    ),
                                    const SizedBox(
                                      height: kDefaultPadding,
                                    ),
                                    Text(
                                      errorMessage.toString(),
                                      style: TextStyle(color: kPrimaryTextColor, fontSize: 16),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(
                                      height: kDefaultPadding,
                                    ),
                                    if (!serviceProcessedError)
                                      Container(
                                        height: 56,
                                        child: RawMaterialButton(
                                          elevation: 0,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          fillColor: kBackgroundColor,
                                          padding: EdgeInsets.symmetric(horizontal: kDefaultPadding),
                                          onPressed: () async {
                                            // await resetAmount(bottomSheetState: _bottomSheetState);
                                            await resetFlow(bottomSheetState: _bottomSheetState);

                                            _bottomSheetState!(() {
                                              // installmentSelected = null;
                                              if (selectedPaymentType == 'CREDIT') {
                                                installmentSelected = null;
                                              }
                                              installmentsData = null;
                                              errorMessage = null;
                                              successMessage = null;
                                              sending = false;
                                              successQrCodePix = false;
                                              imageQrCodePix = null;
                                            });

                                            if (selectedPaymentType == 'DEBIT' || selectedPaymentType == 'PIX') {
                                              Navigator.pop(context);
                                            }
                                          },
                                          child: Row(
                                            crossAxisAlignment: CrossAxisAlignment.center,
                                            mainAxisSize: MainAxisSize.max,
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Text(tr('label_back'),
                                                  style: AppTextStyles.button.copyWith(color: AppColors.neutrals00Bg)),
                                            ],
                                          ),
                                        ),
                                      ),
                                    if (refundProcessed)
                                      Container(
                                        height: 56,
                                        child: RawMaterialButton(
                                          elevation: 0,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          fillColor: kBackgroundColor,
                                          padding: EdgeInsets.symmetric(horizontal: kDefaultPadding),
                                          onPressed: () async {
                                            await resetAmount(bottomSheetState: _bottomSheetState);

                                            _bottomSheetState!(() {
                                              installmentSelected = null;
                                              installmentsData = null;
                                              errorMessage = null;
                                              successMessage = null;
                                              sending = false;
                                            });

                                            Navigator.pop(context);
                                            Navigator.push(context,
                                                MaterialPageRoute(builder: (_) => HomeScreen(account: account, pageIndex: 0)));
                                          },
                                          child: Row(
                                            crossAxisAlignment: CrossAxisAlignment.center,
                                            mainAxisSize: MainAxisSize.max,
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                'Fechar',
                                                style: AppTextStyles.button.copyWith(
                                                  color: AppColors.neutrals00Bg,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    if (serviceProcessedError && !refundProcessed)
                                      Container(
                                        height: 56,
                                        child: RawMaterialButton(
                                          elevation: 0,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          fillColor: AppColors.deliveryVermelhopocket500,
                                          padding: EdgeInsets.symmetric(horizontal: kDefaultPadding),
                                          onPressed: () async {
                                            await _processRefund();
                                          },
                                          child: Row(
                                            crossAxisAlignment: CrossAxisAlignment.center,
                                            mainAxisSize: MainAxisSize.max,
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              const SizedBox(
                                                width: 5,
                                              ),
                                              Text(
                                                'Estonar pagamento',
                                                style: AppTextStyles.button.copyWith(
                                                  color: AppColors.neutrals00Bg,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                  ],
                                );
                              }

                              ///Conteúdo sem parcela selecionada
                              if (installmentSelected == null) {
                                return Column(
                                  children: [
                                    const SizedBox(
                                      height: kDefaultPadding,
                                    ),
                                    Text(
                                      NumberUtils.formatCurrency(txnAmount, account.currencySymbol!, isShowSymbol: true),
                                      style: TextStyle(color: kPrimaryColor, fontWeight: FontWeight.w500, fontSize: 34),
                                    ),
                                    const SizedBox(
                                      height: kDefaultPadding,
                                    ),
                                    Text(
                                      'Valor da cobrança',
                                      style: TextStyle(color: kPrimaryTextColor, fontWeight: FontWeight.w500, fontSize: 14),
                                    ),
                                    const SizedBox(
                                      height: kDefaultPadding,
                                    ),
                                    ListView.builder(
                                      padding: EdgeInsets.fromLTRB(0, kDefaultPadding, 0, 0),
                                      shrinkWrap: true,
                                      physics: ClampingScrollPhysics(),
                                      itemCount: installments.length,
                                      itemBuilder: (context, index) {
                                        Installment installment = installments[index];
                                        String label =
                                            '${installment.times} x ${NumberUtils.formatCurrency(installment.value, account.currencySymbol ?? '', isShowSymbol: true)}';
                                        return Container(
                                          height: 56,
                                          margin: EdgeInsets.fromLTRB(0, 0, 0, kDefaultPadding),
                                          padding: EdgeInsets.fromLTRB(kDefaultPadding, 0, kDefaultPadding, 0),
                                          decoration: BoxDecoration(
                                            color: kPrimaryTextColorLight.withAlpha(30),
                                            borderRadius: BorderRadius.circular(4.0),
                                          ),
                                          child: InkWell(
                                            onTap: () async {
                                              // _bottomSheetState!(() {
                                              setState(() {
                                                installmentSelected = installment;
                                                installmentsData = _installmentsData;
                                              });
                                              _setAmountToPay(setState);
                                            },
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                  crossAxisAlignment: CrossAxisAlignment.center,
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        label,
                                                        style: AppTextStyles.bodymedium,
                                                      ),
                                                    ),
                                                    Icon(
                                                      Icons.arrow_forward_ios_outlined,
                                                      color: kPrimaryColor,
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                );
                              } else {
                                ///Conteúdo com parcela selecionada
                                String installmentsPlural = (installmentSelected!.times ?? 1) > 1 ? 'parcelas' : 'parcela';

                                return Column(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Text(
                                      // selectedPaymentType == 'CREDIT' ? 'Crédito' : 'Débito',
                                      selectedPaymentType == 'CREDIT'
                                          ? 'Crédito'
                                          : selectedPaymentType == 'DEBIT'
                                              ? 'Débito'
                                              : 'Pix',
                                      style: AppTextStyles.titlelarge,
                                    ),
                                    const SizedBox(
                                      height: kDefaultPadding,
                                    ),
                                    Text(
                                      NumberUtils.formatCurrency(amount, account.currencySymbol!, isShowSymbol: true),
                                      style: TextStyle(color: kPrimaryColor, fontWeight: FontWeight.w500, fontSize: 34),
                                    ),
                                    const SizedBox(
                                      height: kDefaultPadding,
                                    ),
                                    if (selectedPaymentType == 'CREDIT')
                                      Text(
                                        'Valor da cobrança',
                                        style: TextStyle(color: kPrimaryTextColor, fontWeight: FontWeight.w500, fontSize: 14),
                                      ),
                                    if (selectedPaymentType == 'CREDIT')
                                      const SizedBox(
                                        height: kDefaultPadding,
                                      ),
                                    if (selectedPaymentType == 'CREDIT')
                                      Text(
                                        '${tr('label_in_str')} ${installmentSelected!.times} $installmentsPlural ${tr('label_of_str')} ${NumberUtils.formatCurrency(installmentSelected!.value, account.currencySymbol!, isShowSymbol: true)}',
                                        style: TextStyle(fontSize: 18),
                                      ),
                                    if (selectedPaymentType == 'CREDIT')
                                      const SizedBox(
                                        height: kDefaultPadding,
                                      ),
                                    Container(
                                      height: 56,
                                      child: RawMaterialButton(
                                        // elevation: btnElevation,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        fillColor: kPrimaryColor,
                                        padding: EdgeInsets.symmetric(horizontal: kDefaultPadding),
                                        onPressed: () async {
                                          if (sending == false) await _processPayment(selectedPaymentType, setState);
                                        },
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.center,
                                          mainAxisSize: MainAxisSize.max,
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            if (sending == false)
                                              Icon(selectedPaymentType == 'PIX' ? Icons.pix : Icons.credit_card,
                                                  color: AppColors.neutrals900),
                                            if (sending == true)
                                              const SizedBox(
                                                  width: 20,
                                                  height: 20,
                                                  child: CircularProgressIndicator(
                                                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.neutrals900),
                                                  )),
                                            if (sending == false)
                                              const SizedBox(
                                                width: 5,
                                              ),
                                            if (sending == false)
                                              Text(
                                                selectedPaymentType == 'PIX' ? 'Avançar' : tr('page_pos.label_btn_charge'),
                                                style: AppTextStyles.button.copyWith(color: AppColors.neutrals900),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(
                                      height: kDefaultPadding,
                                    ),
                                    Container(
                                      height: 56,
                                      child: RawMaterialButton(
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        fillColor: kBackgroundColor,
                                        padding: EdgeInsets.symmetric(horizontal: kDefaultPadding),
                                        onPressed: () async {
                                          setState(() {
                                            installmentSelected = null;
                                          });
                                          if (selectedPaymentType == 'DEBIT' || selectedPaymentType == 'PIX') {
                                            Navigator.pop(context);
                                          }
                                        },
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.center,
                                          mainAxisSize: MainAxisSize.max,
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            const SizedBox(
                                              width: 5,
                                            ),
                                            Text(
                                              tr('label_back'),
                                              style: AppTextStyles.button.copyWith(color: AppColors.neutrals00Bg),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              }
                            }

                            return Container();
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );

        // return StatefulBuilder(
        //   builder: (BuildContext context, StateSetter setState) {
        //     _bottomSheetState = setState;
        //
        //     return FractionallySizedBox(
        //       heightFactor: 0.8,
        //       child: WillPopScope(
        //         onWillPop: () async {
        //           // Condição para permitir ou impedir o fechamento
        //           if (!serviceProcessedError) {
        //             return true; // Permite o fechamento
        //           } else {
        //             return false; // Impede o fechamento
        //           }
        //         },
        //         child: Scaffold(
        //           backgroundColor: Colors.transparent,
        //           appBar: AppBar(
        //             backgroundColor: Colors.transparent,
        //             automaticallyImplyLeading: false,
        //             elevation: 0,
        //             title: _buildProcessTitle(
        //               installmentSelected: installmentSelected,
        //               sending: sending,
        //               sendingProcessPaymentTxn: sendingProcessPaymentTxn,
        //               successMessage: successMessage,
        //               errorMessage: errorMessage,
        //             ),
        //             actions: [
        //               if (!serviceProcessedError)
        //                 IconButton(
        //                   onPressed: () async {
        //                     if (!paymentProcessed) {
        //                       await resetFlow(bottomSheetState: _bottomSheetState);
        //                     } else {
        //                       await resetAmount(bottomSheetState: _bottomSheetState);
        //                     }
        //                     Navigator.pop(context);
        //                   },
        //                   icon: Icon(
        //                     Icons.close,
        //                     color: AppColors.neutrals00Bg,
        //                   ),
        //                 ),
        //             ],
        //           ),
        //           body: Center(
        //             child: SingleChildScrollView(
        //               padding: const EdgeInsets.symmetric(horizontal: kDefaultPaddingLeftRight),
        //               child: BlocBuilder<CreditCardOptionCubit, CreditCardOptionState>(
        //                 builder: (context, state) {
        //                   if (state.isType(CreditCardOptionStates.loading)) {
        //                     return const CircularProgressIndicator(); // Substitua pelo shimmer original
        //                   }
        //
        //                   if (state.isType(CreditCardOptionStates.loaded)) {
        //                     CreditCardPaymentOptions _installmentsData = state.payload;
        //                     List<Installment>? installments = _installmentsData.installments ?? [];
        //
        //                     BlocProvider.of<PaymentFlowCubit>(context).setCreditCardPaymentOptions(_installmentsData);
        //
        //                     ///Conteúdo processando txn
        //                     if (sendingProcessPaymentTxn) {
        //                       return Column(
        //                         mainAxisSize: MainAxisSize.min,
        //                         mainAxisAlignment: MainAxisAlignment.center,
        //                         crossAxisAlignment: CrossAxisAlignment.center,
        //                         children: [
        //                           const SizedBox(
        //                             height: kDefaultPadding,
        //                           ),
        //                           const Icon(
        //                             Icons.more_horiz,
        //                             color: kPrimaryColor,
        //                             size: 62,
        //                           ),
        //                           const SizedBox(
        //                             height: kDefaultPadding,
        //                           ),
        //                           Text(
        //                             'Processando, aguarde...',
        //                             style: TextStyle(color: kPrimaryTextColor, fontSize: 16),
        //                           ),
        //                           const SizedBox(
        //                             height: kDefaultPadding,
        //                           ),
        //                         ],
        //                       );
        //                     }
        //
        //                     ///Conteúdo aguardando confirmação pix
        //                     if (pixProcessing) {
        //                       return Column(
        //                         mainAxisSize: MainAxisSize.min,
        //                         mainAxisAlignment: MainAxisAlignment.center,
        //                         crossAxisAlignment: CrossAxisAlignment.center,
        //                         children: [
        //                           const SizedBox(
        //                             height: kDefaultPadding,
        //                           ),
        //                           const Icon(
        //                             Icons.more_horiz,
        //                             color: kPrimaryColor,
        //                             size: 62,
        //                           ),
        //                           const SizedBox(
        //                             height: kDefaultPadding,
        //                           ),
        //                           Text(
        //                             'Processando transferência, aguarde...',
        //                             style: TextStyle(color: kPrimaryTextColor, fontSize: 16),
        //                           ),
        //                           const SizedBox(
        //                             height: kDefaultPadding,
        //                           ),
        //                         ],
        //                       );
        //                     }
        //
        //                     ///Conteúdo txn sucesso
        //                     if (successMessage != null) {
        //                       return Column(
        //                         mainAxisSize: MainAxisSize.min,
        //                         mainAxisAlignment: MainAxisAlignment.center,
        //                         crossAxisAlignment: CrossAxisAlignment.center,
        //                         children: [
        //                           const SizedBox(
        //                             height: kDefaultPadding,
        //                           ),
        //                           const Icon(
        //                             Icons.check_circle_rounded,
        //                             color: kPrimaryColor,
        //                             size: 62,
        //                           ),
        //                           const SizedBox(
        //                             height: kDefaultPadding,
        //                           ),
        //                           Text(
        //                             successMessage.toString(),
        //                             style: TextStyle(color: kPrimaryTextColor, fontSize: 16),
        //                             textAlign: TextAlign.center,
        //                           ),
        //                           const SizedBox(
        //                             height: kDefaultPadding,
        //                           ),
        //                           Container(
        //                             height: 56,
        //                             child: RawMaterialButton(
        //                               elevation: 0,
        //                               shape: RoundedRectangleBorder(
        //                                 borderRadius: BorderRadius.circular(8),
        //                               ),
        //                               fillColor: kBackgroundColor,
        //                               padding: EdgeInsets.symmetric(horizontal: kDefaultPadding),
        //                               onPressed: () async {
        //                                 await resetAmount(bottomSheetState: _bottomSheetState);
        //                                 Navigator.pop(context);
        //                                 Navigator.push(context,
        //                                     MaterialPageRoute(builder: (_) => HomeScreen(account: account, pageIndex: 0)));
        //                               },
        //                               child: Row(
        //                                 crossAxisAlignment: CrossAxisAlignment.center,
        //                                 mainAxisSize: MainAxisSize.max,
        //                                 mainAxisAlignment: MainAxisAlignment.center,
        //                                 children: [
        //                                   const SizedBox(
        //                                     width: 5,
        //                                   ),
        //                                   Text(tr('label_close'),
        //                                       style: AppTextStyles.button.copyWith(color: AppColors.neutrals00Bg)),
        //                                 ],
        //                               ),
        //                             ),
        //                           ),
        //                         ],
        //                       );
        //                     }
        //
        //                     ///conteúdo processanbdo refund
        //                     if (sendingProcessRefundPaymentTxn) {
        //                       return Column(
        //                         mainAxisSize: MainAxisSize.min,
        //                         mainAxisAlignment: MainAxisAlignment.center,
        //                         crossAxisAlignment: CrossAxisAlignment.center,
        //                         children: [
        //                           const SizedBox(
        //                             height: kDefaultPadding,
        //                           ),
        //                           const Icon(
        //                             Icons.more_horiz,
        //                             color: kPrimaryColor,
        //                             size: 62,
        //                           ),
        //                           const SizedBox(
        //                             height: kDefaultPadding,
        //                           ),
        //                           Text(
        //                             'Processando estorno, aguarde...',
        //                             style: TextStyle(color: kPrimaryTextColor, fontSize: 16),
        //                           ),
        //                           const SizedBox(
        //                             height: kDefaultPadding,
        //                           ),
        //                         ],
        //                       );
        //                     }
        //
        //                     ///Conteúdo txn erro
        //                     if (errorMessage != null) {
        //                       return Column(
        //                         mainAxisSize: MainAxisSize.min,
        //                         mainAxisAlignment: MainAxisAlignment.center,
        //                         crossAxisAlignment: CrossAxisAlignment.center,
        //                         children: [
        //                           Icon(
        //                             Icons.info,
        //                             color: serviceProcessedError && refundProcessed ? kPrimaryColor : kTextColorError,
        //                             size: 62,
        //                           ),
        //                           const SizedBox(
        //                             height: kDefaultPadding,
        //                           ),
        //                           Text(
        //                             errorMessage.toString(),
        //                             style: TextStyle(color: kPrimaryTextColor, fontSize: 16),
        //                             textAlign: TextAlign.center,
        //                           ),
        //                           const SizedBox(
        //                             height: kDefaultPadding,
        //                           ),
        //                           if (!serviceProcessedError)
        //                             Container(
        //                               height: 56,
        //                               child: RawMaterialButton(
        //                                 elevation: 0,
        //                                 shape: RoundedRectangleBorder(
        //                                   borderRadius: BorderRadius.circular(8),
        //                                 ),
        //                                 fillColor: kBackgroundColor,
        //                                 padding: EdgeInsets.symmetric(horizontal: kDefaultPadding),
        //                                 onPressed: () async {
        //                                   await resetAmount(bottomSheetState: _bottomSheetState);
        //
        //                                   _bottomSheetState!(() {
        //                                     installmentSelected = null;
        //                                     installmentsData = null;
        //                                     errorMessage = null;
        //                                     successMessage = null;
        //                                     sending = false;
        //                                   });
        //                                 },
        //                                 child: Row(
        //                                   crossAxisAlignment: CrossAxisAlignment.center,
        //                                   mainAxisSize: MainAxisSize.max,
        //                                   mainAxisAlignment: MainAxisAlignment.center,
        //                                   children: [
        //                                     const SizedBox(
        //                                       width: 5,
        //                                     ),
        //                                     Text(tr('label_back'),
        //                                         style: AppTextStyles.button.copyWith(color: AppColors.neutrals00Bg)),
        //                                   ],
        //                                 ),
        //                               ),
        //                             ),
        //                           if (refundProcessed)
        //                             Container(
        //                               height: 56,
        //                               child: RawMaterialButton(
        //                                 elevation: 0,
        //                                 shape: RoundedRectangleBorder(
        //                                   borderRadius: BorderRadius.circular(8),
        //                                 ),
        //                                 fillColor: kBackgroundColor,
        //                                 padding: EdgeInsets.symmetric(horizontal: kDefaultPadding),
        //                                 onPressed: () async {
        //                                   await resetAmount(bottomSheetState: _bottomSheetState);
        //
        //                                   _bottomSheetState!(() {
        //                                     installmentSelected = null;
        //                                     installmentsData = null;
        //                                     errorMessage = null;
        //                                     successMessage = null;
        //                                     sending = false;
        //                                   });
        //
        //                                   Navigator.pop(context);
        //                                   Navigator.push(context,
        //                                       MaterialPageRoute(builder: (_) => HomeScreen(account: account, pageIndex: 0)));
        //                                 },
        //                                 child: Row(
        //                                   crossAxisAlignment: CrossAxisAlignment.center,
        //                                   mainAxisSize: MainAxisSize.max,
        //                                   mainAxisAlignment: MainAxisAlignment.center,
        //                                   children: [
        //                                     const SizedBox(
        //                                       width: 5,
        //                                     ),
        //                                     Text(
        //                                       'Fechar',
        //                                       style: AppTextStyles.button.copyWith(
        //                                         color: AppColors.neutrals00Bg,
        //                                       ),
        //                                     ),
        //                                   ],
        //                                 ),
        //                               ),
        //                             ),
        //                           if (serviceProcessedError && !refundProcessed)
        //                             Container(
        //                               height: 56,
        //                               child: RawMaterialButton(
        //                                 elevation: 0,
        //                                 shape: RoundedRectangleBorder(
        //                                   borderRadius: BorderRadius.circular(8),
        //                                 ),
        //                                 fillColor: AppColors.deliveryVermelhopocket500,
        //                                 padding: EdgeInsets.symmetric(horizontal: kDefaultPadding),
        //                                 onPressed: () async {
        //                                   await _processRefund();
        //
        //                                   // _bottomSheetState!(() {
        //                                   //   installmentSelected = null;
        //                                   //   installmentsData = null;
        //                                   //   errorMessage = null;
        //                                   //   successMessage = null;
        //                                   //   sending = false;
        //                                   // });
        //                                 },
        //                                 child: Row(
        //                                   crossAxisAlignment: CrossAxisAlignment.center,
        //                                   mainAxisSize: MainAxisSize.max,
        //                                   mainAxisAlignment: MainAxisAlignment.center,
        //                                   children: [
        //                                     const SizedBox(
        //                                       width: 5,
        //                                     ),
        //                                     Text(
        //                                       'Estonar pagamento',
        //                                       style: AppTextStyles.button.copyWith(
        //                                         color: AppColors.neutrals00Bg,
        //                                       ),
        //                                     ),
        //                                   ],
        //                                 ),
        //                               ),
        //                             ),
        //                         ],
        //                       );
        //                     }
        //
        //                     ///Conteúdo sem parcela selecionada
        //                     if (installmentSelected == null) {
        //                       return Column(
        //                         children: [
        //                           const SizedBox(
        //                             height: kDefaultPadding,
        //                           ),
        //                           Text(
        //                             NumberUtils.formatCurrency(txnAmount, account.currencySymbol!, isShowSymbol: true),
        //                             style: TextStyle(color: kPrimaryColor, fontWeight: FontWeight.w500, fontSize: 34),
        //                           ),
        //                           const SizedBox(
        //                             height: kDefaultPadding,
        //                           ),
        //                           Text(
        //                             'Valor da cobrança',
        //                             style: TextStyle(color: kPrimaryTextColor, fontWeight: FontWeight.w500, fontSize: 14),
        //                           ),
        //                           const SizedBox(
        //                             height: kDefaultPadding,
        //                           ),
        //                           ListView.builder(
        //                             padding: EdgeInsets.fromLTRB(0, kDefaultPadding, 0, 0),
        //                             shrinkWrap: true,
        //                             physics: ClampingScrollPhysics(),
        //                             itemCount: installments.length,
        //                             itemBuilder: (context, index) {
        //                               Installment installment = installments[index];
        //                               String label =
        //                                   '${installment.times} x ${NumberUtils.formatCurrency(installment.value, account.currencySymbol ?? '', isShowSymbol: true)}';
        //                               return Container(
        //                                 height: 56,
        //                                 margin: EdgeInsets.fromLTRB(0, 0, 0, kDefaultPadding),
        //                                 padding: EdgeInsets.fromLTRB(kDefaultPadding, 0, kDefaultPadding, 0),
        //                                 decoration: BoxDecoration(
        //                                   color: kPrimaryTextColorLight.withAlpha(30),
        //                                   borderRadius: BorderRadius.circular(4.0),
        //                                 ),
        //                                 child: InkWell(
        //                                   onTap: () async {
        //                                     _bottomSheetState!(() {
        //                                       installmentSelected = installment;
        //                                       installmentsData = _installmentsData;
        //                                     });
        //                                     _setAmountToPay();
        //                                   },
        //                                   child: Column(
        //                                     mainAxisSize: MainAxisSize.min,
        //                                     mainAxisAlignment: MainAxisAlignment.center,
        //                                     crossAxisAlignment: CrossAxisAlignment.start,
        //                                     children: [
        //                                       Row(
        //                                         mainAxisAlignment: MainAxisAlignment.spaceBetween,
        //                                         crossAxisAlignment: CrossAxisAlignment.center,
        //                                         children: [
        //                                           Expanded(
        //                                             child: Text(
        //                                               label,
        //                                               style: AppTextStyles.bodymedium,
        //                                             ),
        //                                           ),
        //                                           Icon(
        //                                             Icons.arrow_forward_ios_outlined,
        //                                             color: kPrimaryColor,
        //                                           ),
        //                                         ],
        //                                       ),
        //                                     ],
        //                                   ),
        //                                 ),
        //                               );
        //                             },
        //                           ),
        //                         ],
        //                       );
        //                     } else {
        //                       ///Conteúdo com parcela selecionada
        //                       String installmentsPlural = (installmentSelected!.times ?? 1) > 1 ? 'parcelas' : 'parcela';
        //                       return Column(
        //                         mainAxisSize: MainAxisSize.min,
        //                         mainAxisAlignment: MainAxisAlignment.center,
        //                         crossAxisAlignment: CrossAxisAlignment.center,
        //                         children: [
        //                           Text(
        //                             NumberUtils.formatCurrency(amount, account.currencySymbol!, isShowSymbol: true),
        //                             style: TextStyle(color: kPrimaryColor, fontWeight: FontWeight.w500, fontSize: 34),
        //                           ),
        //                           const SizedBox(
        //                             height: kDefaultPadding,
        //                           ),
        //                           Text(
        //                             'Valor da cobrança',
        //                             style: TextStyle(color: kPrimaryTextColor, fontWeight: FontWeight.w500, fontSize: 14),
        //                           ),
        //                           const SizedBox(
        //                             height: kDefaultPadding,
        //                           ),
        //                           Text(
        //                             '${tr('label_in_str')} ${installmentSelected!.times} $installmentsPlural ${tr('label_of_str')} ${NumberUtils.formatCurrency(installmentSelected!.value, account.currencySymbol!, isShowSymbol: true)}',
        //                             style: TextStyle(fontSize: 18),
        //                           ),
        //                           const SizedBox(
        //                             height: kDefaultPadding,
        //                           ),
        //                           Container(
        //                             height: 56,
        //                             child: RawMaterialButton(
        //                               // elevation: btnElevation,
        //                               shape: RoundedRectangleBorder(
        //                                 borderRadius: BorderRadius.circular(8),
        //                               ),
        //                               fillColor: kPrimaryColor,
        //                               padding: EdgeInsets.symmetric(horizontal: kDefaultPadding),
        //                               onPressed: () async {
        //                                 if (sending == false) await _processPayment(PaymentPosType.CREDITO_AVISTA, setState);
        //                               },
        //                               child: Row(
        //                                 crossAxisAlignment: CrossAxisAlignment.center,
        //                                 mainAxisSize: MainAxisSize.max,
        //                                 mainAxisAlignment: MainAxisAlignment.center,
        //                                 children: [
        //                                   if (sending == false) Icon(Icons.credit_card, color: AppColors.neutrals900),
        //                                   if (sending == true)
        //                                     const SizedBox(
        //                                         width: 20,
        //                                         height: 20,
        //                                         child: CircularProgressIndicator(
        //                                           valueColor: AlwaysStoppedAnimation<Color>(AppColors.neutrals900),
        //                                         )),
        //                                   if (sending == false)
        //                                     const SizedBox(
        //                                       width: 5,
        //                                     ),
        //                                   if (sending == false)
        //                                     Text(tr('page_pos.label_btn_charge'),
        //                                         style: AppTextStyles.button.copyWith(color: AppColors.neutrals900)),
        //                                 ],
        //                               ),
        //                             ),
        //                           ),
        //                           const SizedBox(
        //                             height: kDefaultPadding,
        //                           ),
        //                           Container(
        //                             height: 56,
        //                             child: RawMaterialButton(
        //                               elevation: 0,
        //                               shape: RoundedRectangleBorder(
        //                                 borderRadius: BorderRadius.circular(8),
        //                                 // side: BorderSide(
        //                                 //   color: kPrimaryColor,
        //                                 //   width: 2.0,
        //                                 // ),
        //                               ),
        //                               fillColor: kBackgroundColor,
        //                               padding: EdgeInsets.symmetric(horizontal: kDefaultPadding),
        //                               onPressed: () async {
        //                                 setState(() {
        //                                   installmentSelected = null;
        //                                 });
        //                               },
        //                               child: Row(
        //                                 crossAxisAlignment: CrossAxisAlignment.center,
        //                                 mainAxisSize: MainAxisSize.max,
        //                                 mainAxisAlignment: MainAxisAlignment.center,
        //                                 children: [
        //                                   const SizedBox(
        //                                     width: 5,
        //                                   ),
        //                                   Text(tr('label_back'),
        //                                       style: AppTextStyles.button.copyWith(color: AppColors.neutrals00Bg)),
        //                                 ],
        //                               ),
        //                             ),
        //                           ),
        //                         ],
        //                       );
        //                     }
        //                   }
        //
        //                   return Container();
        //                 },
        //               ),
        //             ),
        //           ),
        //         ),
        //       ),
        //     );
        //   },
        // );
      },
    );
  }

  /// Constrói o título do processo de pagamento.
  static Widget _buildProcessTitle({
    required Installment? installmentSelected,
    required bool sending,
    required bool sendingProcessPaymentTxn,
    String? successMessage,
    String? errorMessage,
    required String selectedPaymentType,
    required bool pixProcessing,
    required int checkPixAttempts,
    required bool successQrCodePix,
  }) {
    String title = '';
    if (selectedPaymentType == 'DEBIT' || selectedPaymentType == 'PIX') {
      title = 'Revisar pagamento';

      if (installmentSelected != null) {
        title = 'Revisar pagamento';
      }

      if (sending == true) {
        title = 'Aguarde';
      }

      if (pixProcessing) {
        title = 'Aguarde';
      }

      if (!pixProcessing && checkPixAttempts >= 3) {
        title = 'Transferência em processamento';
      }

      if (successQrCodePix) {
        title = 'Pix gerado com sucesso';
      }
      
      // if (successMessage != null && !pixProcessing) {
      if (successMessage != null && !successQrCodePix) {
        title = 'Pagamento realizado';
      }

      if (errorMessage != null && successMessage == null) {
        title = 'Pagamento não processado';
      }

      if (sendingProcessPaymentTxn) {
        title = 'Aguarde';
      }
    } else {
      title = 'Escolha as parcelas';

      if (installmentSelected != null) {
        title = 'Revisar pagamento';
      }

      if (sending == true) {
        title = 'Aguarde';
      }

      if (successQrCodePix) {
        title = 'Pix gerado com sucesso';
      }

      if (successMessage != null && !successQrCodePix) {
        title = 'Pagamento realizado';
      }

      if (errorMessage != null && successMessage == null) {
        title = 'Pagamento não processado';
      }

      if (sendingProcessPaymentTxn) {
        title = 'Aguarde';
      }
    }

    return Text(title, style: AppTextStyles.titlesmall);
  }
  
}
