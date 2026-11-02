
-- Q1. How well is each supplier performing in terms of orders, on-time delivery, quantity delivered, product defects, and delays?

select 
	s.supplier_id,
    s.supplier_name,
    count(distinct po.Po_number) as total_orders,
    round(avg(sh.on_time_flag),2) as on_time_rate,
    round(avg(sh.in_full_flag),2) as fill_rate,
    round(avg(sh.defect_rate_pct),2) as defect_rate,
	round(avg(sh.delay_days),2) as avg_delay_days
from suppliers s 
join purchase_orders po
	on s.supplier_id = po.supplier_id
join shipments sh
	on po.po_number = sh.po_number
group by s.supplier_id,
		s.supplier_name;


-- Q2. Which suppliers are causing the most delivery delays, and how severe are those delays?

select
	po.supplier_id,
    count(*) as total_shipment,
    sum(case
		when sh.delay_days > 0 then 1
        else 0
	end) as delayed_shipments,
   round(avg(sh.delay_days),2) as avg_delay_days,
    round(sum(sh.delay_days),2) as total_delay_days
from purchase_orders po
join shipments sh
	on po.po_number = sh.po_number 
group by po.supplier_id
order by total_delay_days desc;


-- Q3. Which products and warehouse experiences the most stockouts

select
	i.sku_id,
    i.warehouse_code,
    count(*) as month_observed,
    sum(i.stockout_flag) as stockout_months,
    sum(i.units_unmet) as total_unmet_units,
    round(avg(i.days_of_cover),2) as avg_days_of_cover
from inventory_monthly i
group by sku_id, warehouse_code
order by stockout_months desc;


-- Q4. Are we maintaining too much or too little inventory?

select 
	i.sku_id,
    i.warehouse_code,
    round(avg(i.stock_on_hand),2) as avg_stock,
    round(avg(i.safety_stock),2) as avg_safety_stock,
    round(avg(i.days_of_cover),2) as avg_days_of_cover,
    round(avg(i.holding_cost_usd),2) as avg_holding_cost
from inventory_monthly i
group by i.sku_id, i.warehouse_code;



-- Q5. Which suppliers or products have the highest defect rate?

select
	po.supplier_id,
    po.sku_id,
    sum(sh.quantity_rejected) as rejected_units,
    sum(sh.quantity_delivered) as delivered_units,
    round(sum(sh.quantity_rejected)/nullif(sum(sh.quantity_delivered),0) * 100,2) as defect_rate_pct
from purchase_orders po
join shipments sh
	on po.po_number = sh.po_number
group by po.supplier_id, po.sku_id
order by defect_rate_pct desc;



-- Q6. For each supplier and SKU, how many units were rejected, how many were delivered, and what percentage of the delivered units were defective?

select
	po.supplier_id,
    round(sum(po.total_order_value_usd),2) as total_order_value,
    round(sum(sh.freight_cost_usd),2) as total_freight,
    round(sum(sh.freight_cost_usd)/nullif(sum(po.total_order_value_usd),0) *100,2) as freight_pct
from purchase_orders po
join shipments sh
	on po.po_number = sh.po_number
group by po.supplier_id
order by freight_pct desc;


-- Q7. Which products have high demand but poor availability?

select
	i.sku_id,
    round(sum(i.units_demanded),2) as total_demand,
    round(sum(i.units_unmet),2) as total_unmet,
    round(sum(i.units_unmet)/nullif(sum(i.units_demanded),0) * 100,2) as unmet_demand_rate
from inventory_monthly i
group by i.sku_id
order by total_demand desc;

-- Q8. How does promised lead time compare with actual transit time?

SELECT
    po.Supplier_id,
    AVG(sh.Actual_transit_days) AS avg_actual_transit,
    AVG(po.Promised_lead_time_days) AS avg_promised_lead_time,
    AVG(
        sh.Actual_transit_days -
        po.Promised_lead_time_days
    ) AS avg_transit_variance
FROM Purchase_Orders po
JOIN Shipments sh
    ON po.Po_number = sh.Po_number
GROUP BY po.Supplier_id
ORDER BY avg_transit_variance DESC;


-- Q9. What is the overall supply-chain performance trend over time?

SELECT
    YEAR(sh.Ship_date) AS shipment_year,
    MONTH(sh.Ship_date) AS shipment_month,
    COUNT(*) AS shipments,
    ROUND(AVG(sh.On_time_flag) * 100, 2) AS on_time_rate,
    ROUND(AVG(sh.Defect_rate_pct), 2) AS defect_rate,
    ROUND(AVG(sh.Delay_days), 2) AS avg_delay_days,
    SUM(sh.Freight_cost_usd) AS freight_cost
FROM Shipments sh
GROUP BY
    YEAR(sh.Ship_date),
    MONTH(sh.Ship_date)
ORDER BY
    shipment_year,
    shipment_month;


-- Q10. Which suppliers are putting the business at the greatest supply-chain risk?

WITH supplier_metrics AS (
    SELECT
        po.Supplier_id,

        /* Late delivery rate */
        ROUND(
            SUM(CASE
                WHEN sh.On_time_flag = 0 THEN 1
                ELSE 0
            END) / COUNT(*) * 100,
            2
        ) AS late_rate_pct,

        /* Fill rate */
        ROUND(
            SUM(sh.Quantity_delivered) /
            NULLIF(SUM(po.Quantity_ordered), 0) * 100,
            2
        ) AS fill_rate_pct,

        /* Defect rate */
        ROUND(
            SUM(sh.Quantity_rejected) /
            NULLIF(SUM(sh.Quantity_delivered), 0) * 100,
            2
        ) AS defect_rate_pct,

        /* Lead-time variance */
        ROUND(
            AVG(
                sh.Actual_transit_days -
                po.Promised_lead_time_days
            ),
            2
        ) AS avg_lead_time_variance,

        /* Disruption rate */
        ROUND(
            SUM(CASE
                WHEN sh.Disruption_event_id IS NOT NULL THEN 1
                ELSE 0
            END) / COUNT(*) * 100,
            2
        ) AS disruption_rate_pct

    FROM Purchase_Orders po
    JOIN Shipments sh
        ON po.Po_number = sh.Po_number

    GROUP BY
        po.Supplier_id
),

risk_scores AS (
    SELECT
        Supplier_id,
        late_rate_pct,
        fill_rate_pct,
        defect_rate_pct,
        avg_lead_time_variance,
        disruption_rate_pct,

        /* Delivery risk */
        CASE
            WHEN late_rate_pct > 30 THEN 4
            WHEN late_rate_pct > 20 THEN 3
            WHEN late_rate_pct > 10 THEN 2
            ELSE 1
        END AS delivery_risk,

        /* Fill-rate risk */
        CASE
            WHEN fill_rate_pct < 80 THEN 4
            WHEN fill_rate_pct < 90 THEN 3
            WHEN fill_rate_pct < 95 THEN 2
            ELSE 1
        END AS fill_risk,

        /* Quality risk */
        CASE
            WHEN defect_rate_pct > 5 THEN 4
            WHEN defect_rate_pct > 2 THEN 3
            WHEN defect_rate_pct > 1 THEN 2
            ELSE 1
        END AS quality_risk,

        /* Lead-time risk */
        CASE
            WHEN avg_lead_time_variance > 5 THEN 4
            WHEN avg_lead_time_variance > 3 THEN 3
            WHEN avg_lead_time_variance > 1 THEN 2
            ELSE 1
        END AS lead_time_risk,

        /* Disruption risk */
        CASE
            WHEN disruption_rate_pct > 20 THEN 4
            WHEN disruption_rate_pct > 10 THEN 3
            WHEN disruption_rate_pct > 5 THEN 2
            ELSE 1
        END AS disruption_risk

    FROM supplier_metrics
)

SELECT
    s.Supplier_id,
    s.Supplier_name,

    r.late_rate_pct,
    r.fill_rate_pct,
    r.defect_rate_pct,
    r.avg_lead_time_variance,
    r.disruption_rate_pct,

    ROUND(
        r.delivery_risk * 0.30 +
        r.fill_risk * 0.25 +
        r.quality_risk * 0.25 +
        r.lead_time_risk * 0.10 +
        r.disruption_risk * 0.10,
        2
    ) AS supplier_risk_score,

    CASE
        WHEN (
            r.delivery_risk * 0.30 +
            r.fill_risk * 0.25 +
            r.quality_risk * 0.25 +
            r.lead_time_risk * 0.10 +
            r.disruption_risk * 0.10
        ) >= 3.25 THEN 'Critical Risk'

        WHEN (
            r.delivery_risk * 0.30 +
            r.fill_risk * 0.25 +
            r.quality_risk * 0.25 +
            r.lead_time_risk * 0.10 +
            r.disruption_risk * 0.10
        ) >= 2.50 THEN 'High Risk'

        WHEN (
            r.delivery_risk * 0.30 +
            r.fill_risk * 0.25 +
            r.quality_risk * 0.25 +
            r.lead_time_risk * 0.10 +
            r.disruption_risk * 0.10
        ) >= 1.75 THEN 'Medium Risk'

        ELSE 'Low Risk'
    END AS risk_category

FROM risk_scores r

JOIN Suppliers s
    ON r.Supplier_id = s.Supplier_id

ORDER BY
    supplier_risk_score DESC;