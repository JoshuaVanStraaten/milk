curl 'https://www.shoprite.co.za/populateProductsWithHeavyAttributes' \
  -H 'accept: text/plain, */*; q=0.01' \
  -H 'accept-language: en-US,en;q=0.9' \
  -H 'content-type: application/json' \
  -b 'anonymous-consents=%5B%5D; shopriteZA-preferredStore=1894; cookie-notification=NOT_ACCEPTED; cookie-promo-alerts-popup=true; webp_supported=true; JSESSIONID=Y14-b566f1bf-743f-4dfb-a4ab-419c6452d865; geolocation={%22latitude%22:-25.854119003294894%2C%22longitude%22:28.248813830313015%2C%22accuracy%22:61}; AWSALB=uaUZFy51O2f1Dbk1nbB6kJQTSmHI9LAavA2EtyDTnx/D6ub97eTEXZ0R9KZrw9XnILgRUlw3zMW/KX9BBdUBcw576B2K+LNIbdRNREOra91t2KnPvRaRvqY1FDbw; AWSALBCORS=uaUZFy51O2f1Dbk1nbB6kJQTSmHI9LAavA2EtyDTnx/D6ub97eTEXZ0R9KZrw9XnILgRUlw3zMW/KX9BBdUBcw576B2K+LNIbdRNREOra91t2KnPvRaRvqY1FDbw' \
  -H 'csrftoken: ad03ae16-13df-4431-8dbe-81facfc0229b' \
  -H 'origin: https://www.shoprite.co.za' \
  -H 'priority: u=1, i' \
  -H 'referer: https://www.shoprite.co.za/c-2413/All-Departments/Food?q=%3Arelevance%3AbrowseAllStoresFacetOff%3AbrowseAllStoresFacetOff%3AallCategories%3Abakery' \
  -H 'sec-ch-ua: "Not:A-Brand";v="99", "Google Chrome";v="145", "Chromium";v="145"' \
  -H 'sec-ch-ua-mobile: ?0' \
  -H 'sec-ch-ua-platform: "Windows"' \
  -H 'sec-fetch-dest: empty' \
  -H 'sec-fetch-mode: cors' \
  -H 'sec-fetch-site: same-origin' \
  -H 'user-agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36' \
  -H 'x-requested-with: XMLHttpRequest' \
  --data-raw '[{"code":"10810522EA","price":{"value":12.99,"formattedValue":"R12.99","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":false},"hasBabyCategory":"false"},{"code":"10810523EA","price":{"value":15.99,"formattedValue":"R15.99","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":false},"hasBabyCategory":"false"},{"code":"10456482EA","price":{"value":16.99,"formattedValue":"R16.99","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":true},"hasBabyCategory":"false"},{"code":"10397287EA","price":{"value":4.99,"formattedValue":"R4.99","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":false},"hasBabyCategory":"false"},{"code":"10141145EA","price":{"value":11.99,"formattedValue":"R11.99","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":false},"hasBabyCategory":"false"},{"code":"10136370EA","price":{"value":18.99,"formattedValue":"R18.99","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":false},"hasBabyCategory":"false"},{"code":"10141147EA","price":{"value":5,"formattedValue":"R5.00","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":true},"hasBabyCategory":"false"},{"code":"10456150EA","price":{"value":13.99,"formattedValue":"R13.99","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":true},"hasBabyCategory":"false"},{"code":"10151456EA","price":{"value":2.99,"formattedValue":"R2.99","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":false},"hasBabyCategory":"false"},{"code":"10151458EA","price":{"value":2.99,"formattedValue":"R2.99","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":false},"hasBabyCategory":"false"},{"code":"10151456PK1","price":{"value":14.99,"formattedValue":"R14.99","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":false},"hasBabyCategory":"false"},{"code":"10151458PK1","price":{"value":14.99,"formattedValue":"R14.99","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":false},"hasBabyCategory":"false"},{"code":"10136371EA","price":{"value":16.99,"formattedValue":"R16.99","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":false},"hasBabyCategory":"false"},{"code":"10531399EA","price":{"value":9.99,"formattedValue":"R9.99","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":true},"hasBabyCategory":"false"},{"code":"10152503EA","price":{"value":22.99,"formattedValue":"R22.99","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":false},"hasBabyCategory":"false"},{"code":"10351328EA","price":{"value":16.99,"formattedValue":"R16.99","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":false},"hasBabyCategory":"false"},{"code":"10241927EA","price":{"value":17.99,"formattedValue":"R17.99","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":false},"hasBabyCategory":"false"},{"code":"10241931EA","price":{"value":16.99,"formattedValue":"R16.99","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":false},"hasBabyCategory":"false"},{"code":"10151511EA","price":{"value":23.99,"formattedValue":"R23.99","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":false},"hasBabyCategory":"false"},{"code":"10867359EA","price":{"value":23.99,"formattedValue":"R23.99","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":false},"hasBabyCategory":"false"}]'


curl 'https://www.shoprite.co.za/populateProductsWithHeavyAttributes' \
  -H 'accept: text/plain, */*; q=0.01' \
  -H 'accept-language: en-US,en;q=0.9' \
  -H 'content-type: application/json' \
  -b 'anonymous-consents=%5B%5D; shopriteZA-preferredStore=1894; cookie-notification=NOT_ACCEPTED; cookie-promo-alerts-popup=true; webp_supported=true; JSESSIONID=Y14-b566f1bf-743f-4dfb-a4ab-419c6452d865; geolocation={%22latitude%22:-25.854119003294894%2C%22longitude%22:28.248813830313015%2C%22accuracy%22:61}; AWSALB=P4RwL8Lk4spDJfyrd+p2cFUexS6K7IYJKEpTwxV2qMWlxsbFTTGAYxqIbh0kA8rMXrOlVnCcaX7or096SNUzLkDKIej4tpRxFngnFGQfMrQ83YOTxjgxdZaLejBN; AWSALBCORS=P4RwL8Lk4spDJfyrd+p2cFUexS6K7IYJKEpTwxV2qMWlxsbFTTGAYxqIbh0kA8rMXrOlVnCcaX7or096SNUzLkDKIej4tpRxFngnFGQfMrQ83YOTxjgxdZaLejBN' \
  -H 'csrftoken: ad03ae16-13df-4431-8dbe-81facfc0229b' \
  -H 'origin: https://www.shoprite.co.za' \
  -H 'priority: u=1, i' \
  -H 'referer: https://www.shoprite.co.za/c-2413/All-Departments/Food?q=%3Arelevance%3AbrowseAllStoresFacetOff%3AbrowseAllStoresFacetOff%3AallCategories%3Afrozen_food' \
  -H 'sec-ch-ua: "Not:A-Brand";v="99", "Google Chrome";v="145", "Chromium";v="145"' \
  -H 'sec-ch-ua-mobile: ?0' \
  -H 'sec-ch-ua-platform: "Windows"' \
  -H 'sec-fetch-dest: empty' \
  -H 'sec-fetch-mode: cors' \
  -H 'sec-fetch-site: same-origin' \
  -H 'user-agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36' \
  -H 'x-requested-with: XMLHttpRequest' \
  --data-raw '[{"code":"10538316EA","price":{"value":239.99,"formattedValue":"R239.99","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":false},"hasBabyCategory":"false"},{"code":"10705282EA","price":{"value":39.99,"formattedValue":"R39.99","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":false},"hasBabyCategory":"false"},{"code":"10862428EA","price":{"value":184.99,"formattedValue":"R184.99","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":false},"hasBabyCategory":"false"},{"code":"10248591EA","price":{"value":239.99,"formattedValue":"R239.99","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":false},"hasBabyCategory":"false"},{"code":"10253173EA","price":{"value":17.99,"formattedValue":"R17.99","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":false},"hasBabyCategory":"false"},{"code":"10148371KG","price":{"value":89.99,"formattedValue":"R89.99","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":false},"hasBabyCategory":"false"},{"code":"10146965EA","price":{"value":12.99,"formattedValue":"R12.99","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":true},"hasBabyCategory":"false"},{"code":"10138166EA","price":{"value":12.99,"formattedValue":"R12.99","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":true},"hasBabyCategory":"false"},{"code":"10143221EA","price":{"value":28.99,"formattedValue":"R28.99","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":false},"hasBabyCategory":"false"},{"code":"10720096EA","price":{"value":27.99,"formattedValue":"R27.99","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":false},"hasBabyCategory":"false"},{"code":"10711028EA","price":{"value":21.99,"formattedValue":"R21.99","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":false},"hasBabyCategory":"false"},{"code":"10128914EA","price":{"value":29.99,"formattedValue":"R29.99","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":true},"hasBabyCategory":"false"},{"code":"10128127EA","price":{"value":21.99,"formattedValue":"R21.99","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":true},"hasBabyCategory":"false"},{"code":"10800550EA","price":{"value":21.99,"formattedValue":"R21.99","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":false},"hasBabyCategory":"false"},{"code":"10146966EA","price":{"value":21.99,"formattedValue":"R21.99","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":false},"hasBabyCategory":"false"},{"code":"10711035EA","price":{"value":21.99,"formattedValue":"R21.99","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":false},"hasBabyCategory":"false"},{"code":"10126230EA","price":{"value":46.99,"formattedValue":"R46.99","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":false},"hasBabyCategory":"false"},{"code":"10800549EA","price":{"value":21.99,"formattedValue":"R21.99","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":false},"hasBabyCategory":"false"},{"code":"10831297EA","price":{"value":22.99,"formattedValue":"R22.99","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":false},"hasBabyCategory":"false"},{"code":"10458990EA","price":{"value":22.99,"formattedValue":"R22.99","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":false},"hasBabyCategory":"false"}]'

curl 'https://www.shoprite.co.za/populateProductsWithHeavyAttributes' \
  -H 'accept: text/plain, */*; q=0.01' \
  -H 'accept-language: en-US,en;q=0.9' \
  -H 'content-type: application/json' \
  -b 'anonymous-consents=%5B%5D; shopriteZA-preferredStore=1894; cookie-notification=NOT_ACCEPTED; cookie-promo-alerts-popup=true; webp_supported=true; JSESSIONID=Y14-b566f1bf-743f-4dfb-a4ab-419c6452d865; geolocation={%22latitude%22:-25.854119003294894%2C%22longitude%22:28.248813830313015%2C%22accuracy%22:61}; AWSALB=PQhvpu6VEWzwoMRgUHsbLGQiUMzDirX6/U8aCHZzZGdkpCsYbdtO2M3czo0dIod/o1nfE5kQR8py1QIBTb7rHsxSiFKOXG3rDd26bZJFYJMN5+q7Uf4yy/a/ChVm; AWSALBCORS=PQhvpu6VEWzwoMRgUHsbLGQiUMzDirX6/U8aCHZzZGdkpCsYbdtO2M3czo0dIod/o1nfE5kQR8py1QIBTb7rHsxSiFKOXG3rDd26bZJFYJMN5+q7Uf4yy/a/ChVm' \
  -H 'csrftoken: ad03ae16-13df-4431-8dbe-81facfc0229b' \
  -H 'origin: https://www.shoprite.co.za' \
  -H 'priority: u=1, i' \
  -H 'referer: https://www.shoprite.co.za/c-2413/All-Departments/Food?q=%3Arelevance%3AallCategories%3Afresh_fruit%3AbrowseAllStoresFacetOff%3AbrowseAllStoresFacetOff%3AallCategories%3Afresh_vegetables' \
  -H 'sec-ch-ua: "Not:A-Brand";v="99", "Google Chrome";v="145", "Chromium";v="145"' \
  -H 'sec-ch-ua-mobile: ?0' \
  -H 'sec-ch-ua-platform: "Windows"' \
  -H 'sec-fetch-dest: empty' \
  -H 'sec-fetch-mode: cors' \
  -H 'sec-fetch-site: same-origin' \
  -H 'user-agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36' \
  -H 'x-requested-with: XMLHttpRequest' \
  --data-raw '[{"code":"10147186EA","price":{"value":59.99,"formattedValue":"R59.99","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":false},"hasBabyCategory":"false"},{"code":"10152390EA","price":{"value":15.99,"formattedValue":"R15.99","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":false},"hasBabyCategory":"false"},{"code":"10241181EA","price":{"value":16.99,"formattedValue":"R16.99","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":false},"hasBabyCategory":"false"},{"code":"10133089PK3","price":{"value":10,"formattedValue":"R10.00","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":false},"hasBabyCategory":"false"},{"code":"10145033KG","price":{"value":19.99,"formattedValue":"R19.99","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":false},"hasBabyCategory":"false"},{"code":"10148833EA","price":{"value":18.99,"formattedValue":"R18.99","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":false},"hasBabyCategory":"false"},{"code":"10145863EA","price":{"value":22.99,"formattedValue":"R22.99","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":false},"hasBabyCategory":"false"},{"code":"10521297EA","price":{"value":24.99,"formattedValue":"R24.99","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":false},"hasBabyCategory":"false"},{"code":"10734541EA","price":{"value":44.99,"formattedValue":"R44.99","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":false},"hasBabyCategory":"false"},{"code":"10819118EA","price":{"value":39.99,"formattedValue":"R39.99","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":false},"hasBabyCategory":"false"},{"code":"10133089EA","price":{"value":14.99,"formattedValue":"R14.99","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":false},"hasBabyCategory":"false"},{"code":"10144917EA","price":{"value":34.99,"formattedValue":"R34.99","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":false},"hasBabyCategory":"false"},{"code":"10151615EA","price":{"value":29.99,"formattedValue":"R29.99","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":false},"hasBabyCategory":"false"},{"code":"10241180EA","price":{"value":14.99,"formattedValue":"R14.99","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":false},"hasBabyCategory":"false"},{"code":"10155197EA","price":{"value":16.99,"formattedValue":"R16.99","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":false},"hasBabyCategory":"false"},{"code":"10144922EA","price":{"value":19.99,"formattedValue":"R19.99","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":false},"hasBabyCategory":"false"},{"code":"10147193EA","price":{"value":39.99,"formattedValue":"R39.99","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":false},"hasBabyCategory":"false"},{"code":"10155195EA","price":{"value":16.99,"formattedValue":"R16.99","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":false},"hasBabyCategory":"false"},{"code":"10145333PK1","price":{"value":28,"formattedValue":"R28.00","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":false},"hasBabyCategory":"false"},{"code":"10148504EA","price":{"value":14.99,"formattedValue":"R14.99","priceType":"BUY","currencyIso":"ZAR","promotionalPrice":false},"hasBabyCategory":"false"}]'

# All categories:
 Food(4,201)
 Food Cupboard(2,883)
 Fresh Food(917)
 Cooking Ingredients(762)
 Chocolates & Sweets (404)
 Table Condiments & Dressings (249)
 Fresh Meat & Poultry (243)
 Chips, Snacks & Popcorn (226)
 Frozen Food (216)
 Biscuits, Cookies & Cereal Bars (210)
 Yoghurt (190)
 Bakery (178)
 Canned Food (163)
 Breakfast Cereals, Porridge & Pap (157)
 Baking (141)
 Rice, Pasta, Noodles & Cous Cous (122)
 Spreads, Honey & Preserves (107)
 Cooked Meats, Sandwich Fillers & Deli (105)
 Cheese (100)
 Milk, Butter & Eggs (88)
 Biltong, Dried Fruit, Nuts & Seeds (79)
 Frozen Meat & Poultry (76)
 Olives, Gherkins & Pickles (75)
 Bread & Rolls (70)
 Desserts, Jellies & Custards (66)
 Cakes, Cupcakes & Tarts (61)
 Crackers & Crispbreads (61)
 Fresh Fruit (54)
 Frozen Desserts, Ice Cream & Ice (52)
 Fresh Vegetables (48)
 Fresh Salad, Herbs & Dip (42)
 Frozen Vegetables (31)
 Sugar & Sweeteners (31)
 Long Life Milk & Dairy Alternatives (27)
 Fresh & Chilled Desserts (23)
 Ready Meals (23)
 From our Bakery (20)
 Frozen Pies & Party Food (19)
 Frozen Fish & Seafood (15)
 Doughnuts, Fresh Cookies & Iced Buns (12)
 Croissants, Scones & Pastries (7)
 Frozen Chips, Potatoes & Rice (7)
 Frozen Pizza & Garlic Bread (7)
 Platters & Fruit Baskets (7)
 Wraps, Pitas & Naan (6)
 Frozen Vegetarian & Meat Free (5)
 Frozen Fruit & Pastry (4)
 Meat Platters (3)
 Mixed Platters (2)
 Muffins, Pancakes & Waffles (2)
 Chicken & Poultry Platters (1)
 Cocktail & Cheese Platters (1)
 Fresh Fish & Seafood