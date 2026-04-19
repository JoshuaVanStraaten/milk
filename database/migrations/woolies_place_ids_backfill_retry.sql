-- Auto-generated retry pass by backfill_woolies_place_ids_retry.mjs
-- Generated: 2026-04-19T07:10:56.122Z
-- Stores resolved this pass: 14 / 15

BEGIN;
UPDATE public.retailer_stores SET place_id = 'ChIJ9RGqY454zR0RjmQH7yxVqI4', place_nickname = 'Woolworths Mountain Mill Mall' WHERE id = 287;
UPDATE public.retailer_stores SET place_id = 'ChIJ7eWNUrpWzB0R6fwvXgRPWAw', place_nickname = 'Woolworths Food Okavango Crossing' WHERE id = 290;
UPDATE public.retailer_stores SET place_id = 'ChIJifBLjleozR0RsJG0R2Atx9s', place_nickname = 'Woolworths Laborie Centre Paarl' WHERE id = 292;
UPDATE public.retailer_stores SET place_id = 'ChIJ57pcRNm0zR0RudtYmPcPtMQ', place_nickname = 'Woolworths Somerset Mall' WHERE id = 302;
UPDATE public.retailer_stores SET place_id = 'ChIJcSd0jGvgZh4RcnkryJC7KzQ', place_nickname = 'Woolworths Hemingways' WHERE id = 306;
UPDATE public.retailer_stores SET place_id = 'ChIJsXe28LpBzB0RJROE6atInek', place_nickname = 'Woolworths Old Bakery' WHERE id = 319;
UPDATE public.retailer_stores SET place_id = 'ChIJyzO9A4I-lR4RkusEj8DYeuc', place_nickname = 'Woolworths Rynfield Square' WHERE id = 340;
UPDATE public.retailer_stores SET place_id = 'ChIJ-dfWtz2xyB4RRGT75DjJ9o0', place_nickname = 'Woolworths Musina Mall' WHERE id = 341;
UPDATE public.retailer_stores SET place_id = 'ChIJ1UWS94Fpxh4R_VtA29bzZDY', place_nickname = 'Woolworths Makhado Crossing Mall' WHERE id = 342;
UPDATE public.retailer_stores SET place_id = 'ChIJISr_I1BN9h4R5BBuSBQ7-cc', place_nickname = 'Woolworths Galleria Amanzimtoti' WHERE id = 354;
UPDATE public.retailer_stores SET place_id = 'ChIJQQ2JTw3Jvx4Rblb5kD5-Ac0', place_nickname = 'Woolworths Honeyridge Randpark' WHERE id = 369;
UPDATE public.retailer_stores SET place_id = 'ChIJ0XR3wD2Blh4RIMpgARwo1JQ', place_nickname = 'Woolworths Mooiriver Potch' WHERE id = 382;
UPDATE public.retailer_stores SET place_id = 'ChIJu60HgIhmlR4Rw8guZjW1aZU', place_nickname = 'Woolworths Doringkloof' WHERE id = 386;
UPDATE public.retailer_stores SET place_id = 'ChIJo477EK3Fjx4RvGf5uX67bUY', place_nickname = 'Woolworths Café Loch Logan' WHERE id = 387;

COMMIT;
