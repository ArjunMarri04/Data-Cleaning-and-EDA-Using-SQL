SELECT * 
FROM world_layoffs.layoffs;

-- first thing I created a staging table.
CREATE TABLE world_layoffs.layoffs_staging 
LIKE world_layoffs.layoffs;

INSERT layoffs_staging 
SELECT * FROM world_layoffs.layoffs;

-- 1. Remove Duplicates

# First I checked for duplicates

SELECT *
FROM world_layoffs.layoffs_staging
;

SELECT company, industry, total_laid_off,`date`,ROW_NUMBER() OVER (PARTITION BY company, industry, total_laid_off,`date`) AS row_num
FROM world_layoffs.layoffs_staging;



SELECT *
FROM (SELECT company, industry, total_laid_off,`date`,ROW_NUMBER() OVER (PARTITION BY company, industry, total_laid_off,`date`) AS row_num 
      FROM world_layoffs.layoffs_staging) duplicates
WHERE row_num > 1;
    
-- Looked at oda to confirm
SELECT *
FROM world_layoffs.layoffs_staging
WHERE company = 'Oda'
;

-- these are the real duplicates 
SELECT *
FROM (SELECT company, location, industry, total_laid_off,percentage_laid_off,`date`, stage, country, funds_raised,
		ROW_NUMBER() OVER (PARTITION BY company, location, industry, total_laid_off,percentage_laid_off,`date`, stage, country, funds_raised) AS row_num
	    FROM world_layoffs.layoffs_staging) duplicates
WHERE row_num > 1;

-- these are the ones I want to delete where the row number is > 1 or 2or greater essentially

SET SQL_SAFE_UPDATES = 0;

WITH DELETE_CTE AS (
  SELECT *
  FROM (
    SELECT 
      company, location, industry, total_laid_off, percentage_laid_off, `date`, stage, country, funds_raised,
      ROW_NUMBER() OVER (
        PARTITION BY company, location, industry, total_laid_off, percentage_laid_off, `date`, stage, country, funds_raised
      ) AS row_num
    FROM 
      world_layoffs.layoffs_staging
  ) duplicates
  WHERE row_num > 1
)
DELETE FROM world_layoffs.layoffs_staging
WHERE (company, location, industry, total_laid_off, percentage_laid_off, `date`, stage, country, funds_raised) IN (
  SELECT company, location, industry, total_laid_off, percentage_laid_off, `date`, stage, country, funds_raised
  FROM DELETE_CTE
);


SET SQL_SAFE_UPDATES = 1;

SET SQL_SAFE_UPDATES = 0;

WITH DELETE_CTE AS (
  SELECT company, location, industry, total_laid_off, percentage_laid_off, `date`, stage, country, funds_raised,
    ROW_NUMBER() OVER (
      PARTITION BY company, location, industry, total_laid_off, percentage_laid_off, `date`, stage, country, funds_raised
    ) AS row_num
  FROM world_layoffs.layoffs_staging
)
DELETE w
FROM world_layoffs.layoffs_staging w
JOIN DELETE_CTE d
ON w.company = d.company
AND w.location = d.location
AND w.industry = d.industry
AND w.total_laid_off = d.total_laid_off
AND w.percentage_laid_off = d.percentage_laid_off
AND w.date = d.date
AND w.stage = d.stage
AND w.country = d.country
AND w.funds_raised = d.funds_raised
WHERE d.row_num > 1;

SET SQL_SAFE_UPDATES = 1;

-- one solution, which I think is a good one. Is to create a new column and add those row numbers in. Then delete where row numbers are over 2, then delete that column

ALTER TABLE world_layoffs.layoffs_staging ADD row_num INT;


SELECT *
FROM world_layoffs.layoffs_staging
;

CREATE TABLE `world_layoffs`.`layoffs_staging2` (
`company` text,
`location`text,
`industry`text,
`total_laid_off` INT,
`percentage_laid_off` text,
`date` text,
`stage`text,
`country` text,
`funds_raised` int,
row_num INT
);

SET SQL_SAFE_UPDATES = 0;

UPDATE world_layoffs.layoffs_staging
SET total_laid_off = NULLIF(total_laid_off, '')
WHERE total_laid_off = '';


INSERT INTO `world_layoffs`.`layoffs_staging2`
(`company`,
 `location`,
 `industry`,
 `total_laid_off`,
 `percentage_laid_off`,
 `date`,
 `stage`,
 `country`,
 `funds_raised`,
 `row_num`)
SELECT `company`,
       `location`,
       `industry`,
       CASE 
           WHEN total_laid_off REGEXP '^[0-9]+$' THEN CAST(total_laid_off AS UNSIGNED) 
           ELSE NULL 
       END AS total_laid_off,
       `percentage_laid_off`,
       `date`,
       `stage`,
       `country`,
       `funds_raised`,
       ROW_NUMBER() OVER (
         PARTITION BY company, location, industry, total_laid_off, percentage_laid_off, `date`, stage, country, funds_raised
       ) AS row_num
FROM world_layoffs.layoffs_staging;

SET SQL_SAFE_UPDATES = 1;

-- now that we have this we can delete rows were row_num is greater than 2

SET SQL_SAFE_UPDATES = 0;

DELETE FROM world_layoffs.layoffs_staging2
WHERE row_num >= 2;


-- 2. Standardize Data

SELECT * 
FROM world_layoffs.layoffs_staging2;

-- while looking at industry it looks like we have some null and empty rows, let's take a look at these
SELECT DISTINCT industry
FROM world_layoffs.layoffs_staging2
ORDER BY industry;

SELECT *
FROM world_layoffs.layoffs_staging2
WHERE industry IS NULL 
OR industry = ''
ORDER BY industry;

-- take a look at these
SELECT *
FROM world_layoffs.layoffs_staging2
WHERE company LIKE 'Bally%';

-- nothing wrong here
SELECT *
FROM world_layoffs.layoffs_staging2
WHERE company LIKE 'airbnb%';


-- set the blanks to nulls since those are typically easier to work with
UPDATE world_layoffs.layoffs_staging2
SET industry = NULL
WHERE industry = '';

-- now if I check those are all null

SELECT *
FROM world_layoffs.layoffs_staging2
WHERE industry IS NULL 
OR industry = ''
ORDER BY industry;

-- now there is need to populate those nulls if possible

UPDATE layoffs_staging2 t1
JOIN layoffs_staging2 t2
ON t1.company = t2.company
SET t1.industry = t2.industry
WHERE t1.industry IS NULL
AND t2.industry IS NOT NULL;

-- and if checked it looks like Bally's was the only one without a populated row to populate this null values
SELECT *
FROM world_layoffs.layoffs_staging2
WHERE industry IS NULL 
OR industry = ''
ORDER BY industry;

-- ---------------------------------------------------

-- I also noticed the Crypto has multiple different variations. We need to standardize that - let's say all to Crypto
SELECT DISTINCT industry
FROM world_layoffs.layoffs_staging2
ORDER BY industry;

UPDATE layoffs_staging2
SET industry = 'Crypto'
WHERE industry IN ('Crypto Currency', 'CryptoCurrency');

-- now that's taken care of:
SELECT DISTINCT industry
FROM world_layoffs.layoffs_staging2
ORDER BY industry;

-- --------------------------------------------------
-- we also need to look at 

SELECT *
FROM world_layoffs.layoffs_staging2;

-- everything looks good except apparently we have some "United States" and some "United States." with a period at the end. Let's standardize this.
SELECT DISTINCT country
FROM world_layoffs.layoffs_staging2
ORDER BY country;

UPDATE layoffs_staging2
SET country = TRIM(TRAILING '.' FROM country);

-- now if we run this again it is fixed
SELECT DISTINCT country
FROM world_layoffs.layoffs_staging2
ORDER BY country;


-- Let's also fix the date columns:
SELECT *
FROM world_layoffs.layoffs_staging2;

-- we can use str to date to update this field
UPDATE layoffs_staging2
SET `date` = STR_TO_DATE(`date`, '%m/%d/%Y')
WHERE `date` LIKE '%/%';


-- now we can convert the data type properly
ALTER TABLE layoffs_staging2
MODIFY COLUMN `date` DATE;


SELECT *
FROM world_layoffs.layoffs_staging2;





-- 3. Look at Null Values

-- the null values in total_laid_off, percentage_laid_off, and funds_raised all look normal. I don't think I want to change that
-- I like having them null because it makes it easier for calculations during the EDA phase

-- so there isn't anything I want to change with the null values




-- 4. remove any columns and rows we need to

SELECT *
FROM world_layoffs.layoffs_staging2
WHERE total_laid_off IS NULL;


SELECT *
FROM world_layoffs.layoffs_staging2
WHERE total_laid_off IS NULL
AND percentage_laid_off IS NULL;

-- Delete Useless data we can't really use
DELETE FROM world_layoffs.layoffs_staging2
WHERE total_laid_off IS NULL
AND percentage_laid_off IS NULL;

SELECT * 
FROM world_layoffs.layoffs_staging2;

ALTER TABLE layoffs_staging2
DROP COLUMN row_num;


SELECT * 
FROM world_layoffs.layoffs_staging2;