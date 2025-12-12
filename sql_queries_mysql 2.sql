


/***** 1) Total sales, profit, quantity (overall) *****/
SELECT
  SUM(Sales)       AS total_sales,
  SUM(Profit)      AS total_profit,
  SUM(Quantity)    AS total_quantity
FROM cleaned_superstore;

---- 1b) By year and month
SELECT
  YEAR(OrderDate) AS year,
  MONTH(OrderDate) AS month,
  SUM(Sales)       AS monthly_sales,
  SUM(Profit)      AS monthly_profit,
  SUM(Quantity)    AS monthly_quantity
FROM cleaned_superstore
GROUP BY YEAR(OrderDate), MONTH(OrderDate)
ORDER BY YEAR(OrderDate), MONTH(OrderDate);

/***** 2) Monthly sales trend (all months) *****/
SELECT
  DATE_FORMAT(OrderDate, '%Y-%m') AS year_month,
  SUM(Sales) AS sales
FROM cleaned_superstore
GROUP BY year_month
ORDER BY year_month;

-- Alternative: last 24 months
SELECT
  DATE_FORMAT(OrderDate, '%Y-%m') AS year_month,
  SUM(Sales) AS sales
FROM cleaned_superstore
WHERE OrderDate >= DATE_SUB(CURDATE(), INTERVAL 24 MONTH)
GROUP BY year_month
ORDER BY year_month;

/***** 3) YoY sales comparison (year over year, month-level) *****/
WITH monthly AS (
  SELECT
    YEAR(OrderDate) AS year,
    MONTH(OrderDate) AS month,
    SUM(Sales) AS sales
  FROM cleaned_superstore
  GROUP BY YEAR(OrderDate), MONTH(OrderDate)
)
SELECT
  curr.year,
  curr.month,
  curr.sales AS sales_current_year,
  prev.sales AS sales_prev_year,
  ROUND(
    CASE WHEN prev.sales IS NULL OR prev.sales = 0 THEN NULL
         ELSE (curr.sales - prev.sales) / prev.sales * 100
    END, 2
  ) AS pct_change_vs_prev_year
FROM monthly curr
LEFT JOIN monthly prev
  ON curr.month = prev.month
  AND curr.year = prev.year + 1
ORDER BY curr.year, curr.month;

/***** 4) Top 10 products by sales *****/
SELECT
  ProductID,
  ProductName,
  Category,
  SubCategory,
  SUM(Sales) AS total_sales,
  SUM(Quantity) AS total_quantity
FROM cleaned_superstore
GROUP BY ProductID, ProductName, Category, SubCategory
ORDER BY total_sales DESC
LIMIT 10;

/***** 5) Top 10 customers by revenue *****/
SELECT
  CustomerID,
  CustomerName,
  SUM(Sales) AS revenue,
  SUM(Profit) AS profit,
  COUNT(DISTINCT OrderID) AS order_count
FROM cleaned_superstore
GROUP BY CustomerID, CustomerName
ORDER BY revenue DESC
LIMIT 10;

/***** 6) Category-wise profit margin *****/
SELECT
  Category,
  SUM(Sales) AS total_sales,
  SUM(Profit) AS total_profit,
  ROUND(
    CASE WHEN SUM(Sales) = 0 THEN NULL
         ELSE SUM(Profit) / SUM(Sales) * 100
    END, 2
  ) AS profit_margin_pct
FROM cleaned_superstore
GROUP BY Category
ORDER BY profit_margin_pct DESC;

/***** 7) Region performance (sales + profit) *****/
SELECT
  Region,
  SUM(Sales) AS total_sales,
  SUM(Profit) AS total_profit,
  ROUND(
    CASE WHEN SUM(Sales) = 0 THEN NULL
         ELSE SUM(Profit) / SUM(Sales) * 100
    END, 2
  ) AS profit_margin_pct
FROM cleaned_superstore
GROUP BY Region
ORDER BY total_sales DESC;

/***** 8) Discount impact on profitability *****/
-- Bucket discounts and examine average profit margin per bucket
SELECT
  discount_bucket,
  COUNT(*) AS orders,
  SUM(Sales) AS sales,
  SUM(Profit) AS profit,
  ROUND(
    CASE WHEN SUM(Sales)=0 THEN NULL ELSE SUM(Profit)/SUM(Sales)*100 END, 2
  ) AS profit_margin_pct,
  ROUND(AVG(Discount)*100,2) AS avg_discount_pct
FROM (
  SELECT *,
    CASE
      WHEN Discount = 0 THEN '0%'
      WHEN Discount > 0 AND Discount <= 0.1 THEN '0-10%'
      WHEN Discount > 0.1 AND Discount <= 0.2 THEN '10-20%'
      WHEN Discount > 0.2 AND Discount <= 0.4 THEN '20-40%'
      ELSE '>40%'
    END AS discount_bucket
  FROM cleaned_superstore
) t
GROUP BY discount_bucket
ORDER BY avg_discount_pct;

/***** 9) Profit loss analysis (items/orders with negative profit) *****/
-- Orders with negative profit (row-level)
SELECT
  OrderID,
  CustomerID,
  CustomerName,
  ProductID,
  ProductName,
  Sales,
  Profit,
  Quantity,
  Discount,
  Region
FROM cleaned_superstore
WHERE Profit < 0
ORDER BY Profit ASC
LIMIT 100;

-- Sum of loss by product
SELECT
  ProductID,
  ProductName,
  SUM(Profit) AS total_profit,
  SUM(Sales) AS total_sales,
  SUM(Quantity) AS total_quantity
FROM cleaned_superstore
GROUP BY ProductID, ProductName
HAVING SUM(Profit) < 0
ORDER BY total_profit ASC;

/***** 10) Segment contribution % (contribution to total sales by segment) *****/
SELECT
  Segment,
  SUM(Sales) AS segment_sales,
  ROUND(SUM(Sales) / (SELECT SUM(Sales) FROM cleaned_superstore) * 100, 2) AS pct_of_total_sales
FROM cleaned_superstore
GROUP BY Segment
ORDER BY segment_sales DESC;

/***** 11) Shipping time calculation (ShipDate - OrderDate) *****/
-- Average shipping days per ship mode / region using DATEDIFF (returns days)
SELECT
  Region,
  ShipMode,
  AVG(DATEDIFF(ShipDate, OrderDate)) AS avg_ship_days,
  MIN(DATEDIFF(ShipDate, OrderDate)) AS min_ship_days,
  MAX(DATEDIFF(ShipDate, OrderDate)) AS max_ship_days
FROM cleaned_superstore
WHERE ShipDate IS NOT NULL AND OrderDate IS NOT NULL
GROUP BY Region, ShipMode
ORDER BY avg_ship_days;

-- Add a column to show shipping_days per order
SELECT
  OrderID,
  OrderDate,
  ShipDate,
  DATEDIFF(ShipDate, OrderDate) AS ship_days
FROM cleaned_superstore
WHERE ShipDate IS NOT NULL AND OrderDate IS NOT NULL
ORDER BY ship_days DESC
LIMIT 100;

/***** 12) Identify outlier orders (High sales or large loss) *****/

SELECT
  cs.OrderID,
  cs.CustomerID,
  cs.ProductID,
  cs.Sales,
  cs.Profit,
  CASE
    WHEN cs.Sales > (s.avg_sales + 3*s.sd_sales) THEN 'High Sales Outlier'
    WHEN cs.Profit < (s.avg_profit - 3*s.sd_profit) THEN 'High Loss Outlier'
    ELSE 'Normal'
  END AS outlier_flag,
  ROUND((cs.Sales - s.avg_sales)/NULLIF(s.sd_sales,0),2) AS sales_zscore,
  ROUND((cs.Profit - s.avg_profit)/NULLIF(s.sd_profit,0),2) AS profit_zscore
FROM cleaned_superstore cs
CROSS JOIN (
  SELECT
    AVG(Sales) AS avg_sales,
    STDDEV_POP(Sales) AS sd_sales,
    AVG(Profit) AS avg_profit,
    STDDEV_POP(Profit) AS sd_profit
  FROM cleaned_superstore
) s
WHERE
  cs.Sales > (s.avg_sales + 3*s.sd_sales)
  OR cs.Profit < (s.avg_profit - 3*s.sd_profit)
ORDER BY outlier_flag, Sales DESC
LIMIT 200;



/* A) Sales and profit by state (useful for mapping) */
SELECT
  State,
  SUM(Sales) AS sales,
  SUM(Profit) AS profit,
  ROUND(CASE WHEN SUM(Sales)=0 THEN NULL ELSE SUM(Profit)/SUM(Sales)*100 END,2) AS profit_margin_pct
FROM cleaned_superstore
GROUP BY State
ORDER BY sales DESC;

/* B) Monthly cohort example (first order month as cohort) */

WITH first_order AS (
  SELECT CustomerID, MIN(OrderDate) AS first_order_date
  FROM cleaned_superstore
  GROUP BY CustomerID
)
SELECT
  DATE_FORMAT(f.first_order_date, '%Y-%m') AS cohort_month,
  DATE_FORMAT(o.OrderDate, '%Y-%m') AS order_month,
  SUM(o.Sales) AS sales
FROM cleaned_superstore o
JOIN first_order f ON o.CustomerID = f.CustomerID
GROUP BY cohort_month, order_month
ORDER BY cohort_month, order_month
LIMIT 100;

