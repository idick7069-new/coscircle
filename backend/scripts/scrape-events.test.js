import assert from 'node:assert/strict';
import test from 'node:test';
import {
  acostaTaiwanEventUrlsFromHtml,
  parseAcostaEventFromHtml,
  parseCosmosOenEventFromHtml,
  parseEventsFromHtml,
  rejectMissingDoujinEvents,
} from './scrape-events.js';

test('parses Doujin event list JSON-LD and merges visible HTML details', () => {
  const html = `
    <html>
      <body>
        <article>
          <h3>ONLY 黑雪狐★ACGN 二手書市集 第2屆 #二手原創Only</h3>
          <a itemprop="url" href="/events/info/2415">活動頁</a>
          <p>
            活動時間： 2026-09-12 ~ 2026-09-13
            活動會場： [北部]台北地下街 1 號廣場
            入場費用： 免費
            活動內容： 原創小說、原創漫畫 ONLY
            主辦單位： 黑雪狐 團隊
          </p>
        </article>
        <script type="application/ld+json">
          {
            "@context": "https://schema.org",
            "@type": "CollectionPage",
            "mainEntity": {
              "@type": "ItemList",
              "numberOfItems": 1,
              "itemListElement": [{
                "@type": "ListItem",
                "position": 1,
                "item": {
                  "@type": "Event",
                  "name": "黑雪狐★ACGN 二手書市集 第2屆 #二手原創Only",
                  "url": "https://www.doujin.com.tw/events/info/2415",
                  "startDate": "2026-09-12",
                  "endDate": "2026-09-13",
                  "description": "原創小說、原創漫畫 ONLY同人活動",
                  "eventStatus": "https://schema.org/EventScheduled",
                  "organizer": {"@type": "Organization", "name": "黑雪狐 團隊"},
                  "image": "https://www.doujin.com.tw/uploads/events/sample_360.webp",
                  "location": {
                    "@type": "Place",
                    "name": "[北部]台北地下街 1 號廣場",
                    "address": "100台灣臺北市中正區市民大道一段100號台北地下街B1"
                  }
                }
              }]
            }
          }
        </script>
      </body>
    </html>
  `;

  const events = parseEventsFromHtml(html);

  assert.equal(events.length, 1);
  assert.deepEqual(events[0], {
    sourceKey: 'doujin-2415',
    sourceType: 1,
    sourceName: '同人誌中心',
    sourceUrl: 'https://www.doujin.com.tw/events/info/2415',
    imageUrl: 'https://www.doujin.com.tw/uploads/events/sample_360.webp',
    category: 'ONLY',
    name: '黑雪狐★ACGN 二手書市集 第2屆 #二手原創Only',
    startDate: '2026-09-12',
    endDate: '2026-09-13',
    venue: '[北部]台北地下街 1 號廣場',
    fee: '免費',
    description: '原創小說、原創漫畫 ONLY同人活動',
    organizer: '黑雪狐 團隊',
    status: 'approved',
  });
});

test('does not reject normal pages that include Cloudflare challenge scripts', () => {
  const html = `
    <html>
      <head><title>同人活動、同人場次</title></head>
      <body>
        <script type="application/ld+json">
          {
            "@context": "https://schema.org",
            "@type": "SaleEvent",
            "name": "CWT-74《台北場》",
            "url": "https://www.doujin.com.tw/events/info/2356",
            "startDate": "2026-12-12",
            "endDate": "2026-12-13",
            "description": "綜合同人活動",
            "eventStatus": "https://schema.org/EventScheduled",
            "organizer": {"@type": "Organization", "name": "CWT同人誌數位有限公司"},
            "location": {"@type": "Place", "name": "國立臺灣大學綜合體育館"}
          }
        </script>
        <script>
          var a = document.createElement('script');
          a.src = '/cdn-cgi/challenge-platform/scripts/jsd/main.js';
        </script>
      </body>
    </html>
  `;

  const events = parseEventsFromHtml(html);

  assert.equal(events.length, 1);
  assert.equal(events[0].sourceKey, 'doujin-2356');
  assert.equal(events[0].category, '綜合');
});

test('parses COSMOS Oen public event page', () => {
  const html = `
    <html>
      <head>
        <meta property="og:image" content="https://static-assets.oen.tw/images/cosmos.jpg" />
      </head>
      <body>
        <h1>【COSMOS】入場門票</h1>
        <div>
          活動已結束
          2026/07/17 (五) 10:00 ~ 07/19 (日) 16:30 (UTC+8)
          國立臺灣大學綜合體育館3樓主球場臺北市 大安區 羅斯福路四段 1 號
          〖COSMOS Cosplay 創作攝影展〗官方活動與售票說明
          ⚡ 活動資訊
          活動地點： 國立臺灣大學綜合體育館 3 樓主球場（臺北市大安區羅斯福路四段1號）。
          🎟️ 售票與票種說明
          一般單日票： NT$ 300 元
        </div>
      </body>
    </html>
  `;

  const event = parseCosmosOenEventFromHtml(
    html,
    'https://cosmos.oen.tw/events/3DGSdlOZgTrm1idEZRYTbUp2f4y',
  );

  assert.equal(event.sourceKey, 'cosmos-oen-entry-ticket-2026');
  assert.equal(event.sourceName, 'COSMOS 創作攝影展');
  assert.equal(event.name, 'COSMOS 創作攝影展');
  assert.equal(event.startDate, '2026-07-17');
  assert.equal(event.endDate, '2026-07-19');
  assert.equal(event.venue, '國立臺灣大學綜合體育館 3 樓主球場');
  assert.equal(event.detailedAddress, '臺北市大安區羅斯福路四段1號');
  assert.equal(event.fee, 'NT$ 300');
  assert.equal(event.imageUrl, 'https://static-assets.oen.tw/images/cosmos.jpg');
});

test('extracts only Taiwan acosta event URLs from the Taiwan area page', () => {
  const html = `
    <a href="/event/takao/26041112/">高雄</a>
    <a href="https://acosta.jp/event/taipei_sccp/26051617/">台北</a>
    <a href="/event/ikebukuro/2026_12/">池袋</a>
    <a href="https://www.facebook.com/acosta.tw/">Facebook</a>
  `;

  assert.deepEqual(acostaTaiwanEventUrlsFromHtml(html), [
    'https://acosta.jp/event/takao/26041112/',
    'https://acosta.jp/event/taipei_sccp/26051617/',
  ]);
});

test('parses public acosta Taiwan event page', () => {
  const html = `
    <html>
      <head>
        <title>2026年5月16日(土)17日(日)acosta!@台北 - acosta!</title>
      </head>
      <body>
        イベント概要 EVENT INFORMATION
        開催日時 2026 5.16sat 17sat 10:00～18:00
        会場 アクセス詳細 松山文創園区 〖受付〗椰林大道 台湾台北市信義区光復南路133号
        チケット情報
        カメラ・一般 10:00~ 前売り1,600 円 (当日販売無し)
      </body>
    </html>
  `;

  const event = parseAcostaEventFromHtml(
    html,
    'https://acosta.jp/event/taipei_sccp/26051617/',
  );

  assert.equal(event.sourceKey, 'acosta-26051617');
  assert.equal(event.sourceName, 'acosta!');
  assert.equal(event.name, 'acosta!@台北');
  assert.equal(event.startDate, '2026-05-16');
  assert.equal(event.endDate, '2026-05-17');
  assert.equal(event.venue, '松山文創園区');
  assert.equal(event.detailedAddress, '台北市信義区光復南路133号');
  assert.equal(event.fee, '1,600 円');
});

test('missing Doujin sync only rejects current or future events', async () => {
  const executed = [];
  const pool = {
    async execute(sql, params) {
      executed.push({ sql, params });
    },
  };

  await rejectMissingDoujinEvents(pool, [
    {
      sourceUrl: 'https://www.doujin.com.tw/events/info/2356',
    },
  ]);

  assert.equal(executed.length, 1);
  assert.match(executed[0].sql, /end_date >= CURRENT_DATE\(\)/);
  assert.deepEqual(executed[0].params, [
    'https://www.doujin.com.tw/events/info/2356',
  ]);
});
