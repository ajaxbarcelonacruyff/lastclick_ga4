with ga AS(
  SELECT *,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key ='ga_session_id') AS ga_session_id,
  -- 新しい参照元から流入した場合は、collected_traffic_source.manual_sourceなどに値が入るので抽出。ただし、(direct)や(not set)などは除外とする
  NULLIF(REGEXP_REPLACE(collected_traffic_source.manual_source,r'(\(direct\)|\(not set\)|\(none\)|\(not provided\))',''), '') AS manual_source,
  NULLIF(REGEXP_REPLACE(collected_traffic_source.manual_medium,r'(\(direct\)|\(not set\)|\(none\)|\(not provided\))',''), '') AS manual_medium,
  NULLIF(REGEXP_REPLACE(collected_traffic_source.manual_campaign_name,r'(\(direct\)|\(not set\)|\(none\)|\(not provided\))',''), '') AS manual_campaign_name,
  FROM `project_id.analytics_property_id.events_YYYYMMDD`
)
-- キャンペーン名などは空の場合もあるため、sourceが存在する行から抽出する必要があるので、sourceが存在する最新の行番号を取得する
, event_order AS(
  SELECT *,
   ROW_NUMBER()OVER(PARTITION BY ga_session_id, user_pseudo_id ORDER BY event_timestamp) AS rn
  FROM ga 
)
, temp_source_order AS(
  SELECT *,
    IF(manual_source IS NOT NULL, rn, NULL) AS source_rn
  FROM event_order 
)
, source_order AS(
  SELECT * EXCEPT(source_rn),
    LAST_VALUE(manual_source IGNORE NULLS) OVER (PARTITION BY user_pseudo_id,ga_session_id ORDER BY event_timestamp ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS latest_manual_source,
    LAST_VALUE(source_rn IGNORE NULLS) OVER (PARTITION BY user_pseudo_id,ga_session_id ORDER BY event_timestamp ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)  AS latest_manual_source_rn,
  FROM temp_source_order
)
-- sourceが存在する行からmedium, campaign_nameを取得し結合
, temp_campaign AS(
  SELECT s.* EXCEPT(manual_medium, manual_campaign_name),
  e.manual_medium AS latest_manual_medium,
  e.manual_campaign_name AS latest_manual_campaign_name,
  FROM source_order s LEFT JOIN event_order e ON s.user_pseudo_id= e.user_pseudo_id AND s.ga_session_id = e.ga_session_id AND s.latest_manual_source_rn = e.rn
)
, result AS(
  SELECT 
  -- 最新の値が存在しない場合（＝セッション中に他からの流入がない）、元々参照元として定義されているsession_traffic_source_last_click.cross_channel_campaignを採用。
  IFNULL(latest_manual_source, session_traffic_source_last_click.cross_channel_campaign.source) AS last_click_source,
  IFNULL(latest_manual_medium, session_traffic_source_last_click.cross_channel_campaign.medium) AS last_click_medium,
  IFNULL(latest_manual_campaign_name, session_traffic_source_last_click.cross_channel_campaign.campaign_name) AS last_click_campaign_name,
  * EXCEPT(latest_manual_source, latest_manual_medium,latest_manual_campaign_name),
FROM temp_campaign
)
SELECT *
FROM result 
;
