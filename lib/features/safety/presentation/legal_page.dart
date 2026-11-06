import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/repositories/legal_repository.dart';

enum LegalDocument { privacy, terms }

class _LegalSection {
  const _LegalSection(this.title, this.paragraphs);

  final String title;
  final List<String> paragraphs;
}

const _privacySections = [
  _LegalSection('1. 服務與營運者', [
    'CosCircle（Cos小圈圈）由 CosCircle 營運團隊提供，協助使用者管理 Cosplay 與同人活動的名片、出席、小圈圈、集合與認親。本政策適用於 CosCircle App、網站及相關帳號服務。',
    '隱私、帳號或資料權利問題，可透過頁面下方的聯絡表單聯絡 CosCircle 營運團隊。',
  ]),
  _LegalSection('2. 帳號與登入資料', [
    '以 Email 註冊時，我們處理電子信箱、暱稱、密碼雜湊、登入憑證及信箱驗證或密碼重設紀錄。密碼以雜湊保存；驗證與重設連結的憑證以雜湊保存。請勿把登入憑證或重設連結交給他人。',
    '使用 LINE 登入或綁定時，我們向 LINE 驗證授權，處理 LINE 使用者識別碼、顯示名稱與大頭貼。CosCircle 不會取得你的 LINE 密碼。LINE 授權憑證用於驗證身分，不作為 CosCircle 的密碼保存。',
    '我們記錄你明確同意的條款與隱私政策版本及時間，以確認適用的使用規則。',
  ]),
  _LegalSection('3. 你提供的內容與互動', [
    '依你使用的功能，我們保存名片暱稱、簡介、照片、外部社群連結、年齡、性別、常跑與遠征地區、互動偏好、地雷及作品坑單。你可自行決定提供哪些選填內容。',
    '活動資料包括出席日期、身分、作品、角色、出角照片、可互動時間、備註與現場狀態。社交資料包括追蹤、封鎖、戳友邀請與自我介紹、小圈圈名稱與成員、集合點、認親訊號及回覆。',
    '提出檢舉或聯絡支援時，我們處理你提交的理由、說明、相關內容與處理紀錄。檢舉可能包含當時可見內容的快照，供管理員查核。檢舉快照、詳細說明與審查備註保留 90 天，到期由定期清理作業移除；刪除帳號時會立即清除與該帳號相關的檢舉個人資料。',
  ]),
  _LegalSection('4. 使用目的與技術資料', [
    '我們使用上述資料提供登入、名片、活動出席、同好與小圈圈互動、位置分享、集合、通知、帳號復原、客服及違規處理，並依你的作品與活動資訊呈現相關同好。',
    '啟用推播時，我們處理裝置推播權杖與平台類型。伺服器及代管服務可能記錄連線 IP、請求時間、錯誤及帳號操作資訊，用於服務維護、防止濫用與排除問題。',
    'App 在裝置保存登入憑證與偏好設定。相機、相簿、位置及通知權限依功能提出請求；你可以在裝置設定管理權限，拒絕權限會限制對應功能。',
  ]),
  _LegalSection('5. 可見性與主動位置分享', [
    '名片、QR Code、活動出席與分享內容依各功能的可見性設定提供。公開名片連結與分享圖可能由取得連結或圖片的人查看及轉傳。請避免在公開欄位填寫住址、電話或其他敏感資料。',
    '上傳圖片目前以公開網址提供，圖片網址本身不要求登入。即使出席資料限制小圈圈可見，知道圖片網址的人仍可能直接查看、複製或轉傳圖片。不要把可見性設定視為圖片存取驗證。',
    '現場功能在你使用 App 並授予前景位置權限時取得位置。你主動分享後，經緯度、活動、分享範圍與到期時間會傳送至伺服器，提供給符合該功能可見條件的使用者。集合點也會保存你選擇的地點。',
    '你可停止分享或使用隱身功能。分享到期會停止對外提供該筆有效位置；這不代表相關資料、伺服器紀錄或備份立刻物理刪除。CosCircle 不要求持續背景定位。',
    '可見性與封鎖功能無法收回他人先前已看到、截圖、下載或轉傳的內容。上傳照片的網址不是獨立的身分驗證保護；取得網址的人可能直接存取或轉傳。伺服器允許照片公開快取最長 30 天，刪除原始檔案後，既有快取仍可能在到期前顯示。',
  ]),
  _LegalSection('6. 代管與第三方服務', [
    'Google Cloud 代管伺服器承載 CosCircle 的 API、資料庫及上傳照片。具維運權限的人員可因服務維護、安全及支援需要處理相關資料。',
    'LINE 提供登入身分驗證。Resend 處理收件信箱及帳號驗證、密碼重設或安全通知的郵件內容。Firebase Cloud Messaging（FCM）處理推播權杖、通知與事件識別資料；通知可能含暱稱及活動互動資訊，並依裝置設定顯示於鎖定畫面。',
    'Google Maps 提供地圖，使用地圖與定位功能時可能依其服務運作處理裝置、連線及位置資訊。聯絡表單使用 Google Forms，你在表單填寫的內容由 Google 與營運團隊處理。這些服務可能於你所在地以外處理資料，並適用各自的隱私政策。',
    '開啟外部活動來源、社群連結或其他網站後，該網站的資料處理由其營運者負責。',
  ]),
  _LegalSection('7. 資料保留與帳號刪除', [
    '帳號使用期間，資料依提供功能、安全及處理請求的需要保存。你可修改名片、取消出席、停止位置分享，或提出刪除帳號。部分互動或管理紀錄不會因單一欄位修改而一併消失。',
    '刪除帳號須重新驗證身分並再次確認。刪除會移除帳號、登入方式、名片、出席、關注與戳友關係、位置、認親等關聯資料。有上傳歸屬紀錄的照片會排入清理，失敗時由背景作業重試；舊版未記錄歸屬的照片交由營運團隊核實後處理，避免誤刪他人的照片。你擁有的小圈圈會解散，相關成員關係與集合點一併移除。刪除後無法復原，也不會刪除你的 LINE 帳號。',
    '他人已保存的分享圖、截圖與轉傳內容不會自動刪除。依法需要保留或處理爭議、安全事件所必要的紀錄，可能在必要範圍內另行保存。',
    '目前尚未確認備份及系統紀錄的具體保留期限與清除週期，因此不承諾固定天數或立即清除全部備份。你可透過聯絡表單詢問個案的保留與刪除情況。',
    '未安裝 App 也可使用公開刪除帳號頁，以 Email 與密碼登入後再次確認刪除。僅使用 LINE、無法登入或無法完成驗證時，可提出人工刪除請求；營運團隊須先核對帳號所有權，不會僅憑未驗證表單刪除帳號。',
  ]),
  _LegalSection('8. 資料權利與聯絡', [
    '你可向 CosCircle 營運團隊提出資料查詢、閱覽、更正、提供副本、停止處理或刪除等請求。處理前可能需要核對帳號所有權；若有法令或他人權益限制，我們會就個案說明。',
    '請在聯絡表單註明「隱私資料請求」或「刪除帳號」、帳號識別資訊及可聯絡方式。不要提交密碼、LINE 密碼、登入權杖或驗證連結。表單本身不是即時客服，也不會自動執行刪除。',
  ]),
  _LegalSection('9. 政策更新', [
    '政策更新會標示版本與生效日期。需要重新確認的版本會在登入後要求你明確勾選同意，再使用主要功能及發布內容；你仍可閱讀文件、登出、檢舉或刪除帳號。',
  ]),
];

const _termsSections = [
  _LegalSection('1. 服務與同意', [
    'CosCircle（Cos小圈圈）由 CosCircle 營運團隊提供，協助使用者管理活動名片、出席、小圈圈、位置分享、集合與認親。使用主要功能及發布內容前，你須明確同意本條款與同版本隱私政策。',
    '你可先閱讀完整文件，再決定是否同意。不同意時可登出、檢舉或刪除帳號。若你依法需要法定代理人同意才能使用服務，應先取得該同意。',
  ]),
  _LegalSection('2. 帳號與身分安全', [
    '提供正確且可使用的帳號資訊，妥善保管密碼與登入憑證。不得冒用他人、轉售帳號、使用他人憑證或規避停權。發現帳號遭冒用時，請透過聯絡表單通知營運團隊。',
    'LINE 登入僅作為身分驗證方式，CosCircle 不會要求 LINE 密碼。帳號復原、綁定及刪除可能要求重新驗證身分。',
  ]),
  _LegalSection('3. 禁止發布與從事的行為', [
    '你對自己發布的名片、照片、出席備註、小圈圈名稱、邀請訊息、集合點、認親回覆及其他內容負責。不得發布違法內容或利用服務從事違法行為。',
    '禁止騷擾、跟蹤、威脅、霸凌、煽動暴力，以及針對種族、族群、國籍、宗教、性別、性傾向、身心障礙等身分的仇恨或歧視攻擊。',
    '禁止違法裸露、色情、未經同意的私密影像與性剝削內容。任何涉及兒童或少年性虐待、性剝削、誘騙或其他危害兒少安全的內容與行為均不允許。',
    '禁止未經授權揭露他人的姓名、聯絡方式、住址、即時位置、私密資訊或照片，亦不得侵害肖像、著作或其他權利。拍攝、轉傳與公開他人照片前，應取得必要授權。',
    '禁止垃圾訊息、詐騙、惡意廣告、冒名、誤導身分、惡意檢舉、自動化濫用、惡意程式、竊取資料或干擾服務。不得利用多個帳號規避封鎖或處置。',
  ]),
  _LegalSection('4. 檢舉、封鎖與現場安全', [
    '遇到違規使用者、出席內容或小圈圈，可使用對應的檢舉功能，選擇原因並補充說明。管理員會查看檢舉及相關可見內容；檢舉資料供管理處理，不作為公開留言。',
    '你可使用封鎖功能限制相關互動，並停止位置分享、調整可見性或離開小圈圈。封鎖不會收回他人先前已保存的內容，也無法保證線下安全。',
    'CosCircle 不是緊急救援服務。遇到即時危險，應聯絡當地緊急服務或現場工作人員。不得利用位置、集合或認親功能追蹤、施壓或接近不願互動的人。',
  ]),
  _LegalSection('5. 違規處置與申訴', [
    '營運團隊可依違規情節、可查證內容與安全需要，移除出席內容或小圈圈、限制功能或停權。涉及違法或安全事件時，可能依法配合有權機關並保存必要紀錄。',
    '對處置有疑問，可透過聯絡表單提出申訴，註明帳號識別資訊、處置情況、理由及相關證據。營運團隊會核對身分並重新檢視可用資料。不得在申訴中提供密碼、登入權杖或未經必要遮蔽的他人私密資訊。',
    '檢舉或申訴不保證特定處置結果，也不保證即時回覆。營運團隊會依安全、隱私及可查證資料處理。',
  ]),
  _LegalSection('6. 內容權利與分享', [
    '你保有自己內容原有的權利，並須確保有權上傳與分享。為提供服務，你授權 CosCircle 在功能所需範圍內儲存、處理及依可見性設定呈現內容，並產生你要求的分享圖。',
    '取得公開連結或分享圖的人可能另行保存或轉傳。刪除內容、改變可見性或刪除帳號，無法自動移除他人裝置、外部網站或社群上的副本。',
  ]),
  _LegalSection('7. 活動資訊與服務限制', [
    '活動資料可能來自外部來源、主辦單位或使用者投稿，時間、地點及規則可能變更。參加前應向主辦單位確認。CosCircle 的出席標記不等於購票、入場資格、約拍契約或主辦單位承諾。',
    '地圖、定位、通知與網路可能延遲或中斷。現場安排應保留其他聯絡方式。營運團隊會維護服務，但無法保證所有資訊即時正確或服務永不中斷；依法不得排除或限制的責任與使用者權利不受本條款影響。',
  ]),
  _LegalSection('8. 離開服務與刪除帳號', [
    '你可登出、停止使用，或經重新驗證及明確確認後刪除帳號。刪除會移除帳號與關聯資料，且無法復原。有上傳歸屬紀錄的照片會排入清理，失敗時由背景作業重試。舊版未記錄歸屬的照片需先由營運團隊核實。你擁有的小圈圈會解散，成員關係與集合點一併移除。',
    '未安裝 App 可使用公開刪除帳號頁，以 Email 與密碼登入後再次確認。僅使用 LINE、無法登入或無法完成驗證時，可經聯絡表單提出人工刪除請求，待核對帳號所有權後處理。',
    '他人保存的分享內容、備份與依法必要保留的紀錄，依隱私政策說明處理。刪除 CosCircle 帳號不會刪除 LINE 帳號。',
  ]),
  _LegalSection('9. 條款更新與聯絡', [
    '條款更新會公布版本與生效日期，需要重新確認時會要求你再次明確同意。你仍可閱讀文件、登出、檢舉或刪除帳號。',
    '服務、權利、檢舉處理及申訴問題，請透過聯絡表單聯絡 CosCircle 營運團隊。本條款不影響依法不得放棄的權利。',
  ]),
];

class LegalPage extends StatelessWidget {
  const LegalPage({super.key, required this.document});

  final LegalDocument document;

  @override
  Widget build(BuildContext context) {
    final privacy = document == LegalDocument.privacy;
    final title = privacy ? '隱私政策' : '使用條款';
    final sections = privacy ? _privacySections : _termsSections;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: SelectionArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 8),
                    const Text('版本與生效日期 $legalVersion'),
                    for (final section in sections) ...[
                      const SizedBox(height: 24),
                      Text(
                        section.title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      for (final paragraph in section.paragraphs)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(paragraph),
                        ),
                    ],
                    const SizedBox(height: 24),
                    TextButton.icon(
                      onPressed: () => _contact(context),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('聯絡 CosCircle 營運團隊（Google Forms）'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _contact(BuildContext context) async {
    try {
      final opened = await launchUrl(
        Uri.parse('https://forms.gle/WGFe57Y1AFW1LQda8'),
        mode: LaunchMode.externalApplication,
      );
      if (opened) return;
    } catch (_) {
      // The offline document remains available when the external form cannot open.
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('無法開啟聯絡表單，請連線後再試')),
    );
  }
}
