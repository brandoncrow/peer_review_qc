/*
  Title: Peer Review QC Script
  Purpose: Quality control checks for client data migration to ensure integrity, completeness, and conformance to business rules.
  Author: Brandon Crow
  Date: 2024-08-01
  Notes:
    - Run in staging environment prior to client go-live.
    - Logs written to #QC_Log for review and sign-off.
*/

--Create a table to log results
DROP TABLE IF EXISTS #QC_Log;
CREATE TABLE #QC_Log (
    QC_LogID INT IDENTITY PRIMARY KEY,
    Area VARCHAR(50),
	Checklist VARCHAR(255),
	Additional_Comments VARCHAR(255),
	[Reviewed - Y/N] VARCHAR(14),
	[Reviewer's Initials] VARCHAR(5),
    Status VARCHAR(10), -- PASS, FAIL, or CHECK
    Reviewed_Date DATETIME DEFAULT GETDATE(),
	ErrorDescription VARCHAR(255),
	Data_Hygienist_Comments VARCHAR(255),
	RecordID INT NULL
);
--#region: Company
--Check if the Company table is populated
INSERT INTO #QC_Log (Area, Checklist, Additional_Comments, ErrorDescription, Status)
SELECT 
	'Company', 
	'Ensure Company table is populated', 
	'PM will get this information from the client if it isn''t easy to get from the source data',
	CASE 
		WHEN NOT EXISTS (SELECT 1 FROM Company) THEN 'Company table is not populated' 
		ELSE 'PASS' 
	END AS ErrorDescription,
	CASE 
		WHEN NOT EXISTS (SELECT 1 FROM Company) THEN 'FAIL' 
		ELSE 'PASS' 
	END AS Status
;
--#endregion: Company
--#region: Agreement
--Check for invalid AgreementName values where AgreementClassCode is not 'CON'
INSERT INTO #QC_Log (Area, RecordID, Checklist, Additional_Comments, ErrorDescription, Status)
SELECT 
	'Agreement', 
	AgreementID, 
	'Check to ensure that Agreement Names are only populated for Contracts', 
	NULL,
	CASE 
		WHEN AgreementClassCode <> 'CON' AND AgreementName IS NOT NULL THEN 'AgreementName is populated for non-CON AgreementClassCode'
		WHEN AgreementClassCode = 'CON' AND AgreementName IS NULL THEN 'AgreementName is not populated for CON AgreementClassCode'
		ELSE 'PASS'
	END AS ErrorDescription,
	CASE 
		WHEN AgreementClassCode = 'CON' AND AgreementName IS NOT NULL THEN 'PASS'
		WHEN AgreementClassCode <> 'CON' AND AgreementName IS NULL THEN 'PASS'
		ELSE 'FAIL'
	END AS Status
FROM Agreement;
--Check that the term/term Areas are populated and expiration dates calculated 
INSERT INTO #QC_Log (Area, RecordID, ErrorDescription, Status, Checklist, Additional_Comments)
SELECT 
	'Agreement',
	AgreementID,
	CASE 
		WHEN Term IS NOT NULL AND TermUnit  IS NOT NULL AND ExpireDateCalc IS NOT NULL AND ExtendedTerm  IS NOT NULL AND ExtendedTermUnit  IS NOT NULL AND ExtendedExpDateCalc  IS NOT NULL THEN 'PASS' 
		ELSE
			NULLIF(CONCAT(
				CASE WHEN (Term IS NOT NULL AND TermUnit IS NOT NULL AND ExpireDateCalc IS NOT NULL) AND (ExtendedTerm IS NULL OR ExtendedTermUnit IS NULL OR ExtendedExpDateCalc IS NULL) THEN 'Refer to source data: ' ELSE '' END,
				CASE WHEN Term IS NULL THEN 'Term is missing; ' ELSE '' END,
				CASE WHEN TermUnit IS NULL THEN 'TermUnit is missing; ' ELSE '' END,
				CASE WHEN ExpireDateCalc IS NULL THEN 'ExpireDateCalc is missing; ' ELSE '' END,
				CASE WHEN ExtendedTerm IS NULL THEN 'ExtendedTerm is missing; ' ELSE '' END,
				CASE WHEN ExtendedTermUnit IS NULL THEN 'ExtendedTermUnit is missing; ' ELSE '' END,
				CASE WHEN ExtendedExpDateCalc IS NULL THEN 'ExtendedExpDateCalc is missing; ' ELSE '' END
			),'') 
	END AS ErrorDescription,
	CASE 
		WHEN Term IS NULL OR TermUnit IS NULL OR ExpireDateCalc IS NULL THEN 'FAIL'
		WHEN ExtendedTerm IS NULL OR ExtendedTermUnit IS NULL OR ExtendedExpDateCalc IS NULL THEN 'CHECK'
		ELSE 'PASS'
	END AS Status,
	'Check that the term/term Areas are populated and expiration dates calculated',
	'If expiration dates are missing, most likely missing term/term unit' + CHAR(10) + 'Also applies for extended expiration dates'
FROM Agreement;
--Check the codes against the validation table
INSERT INTO #QC_Log (Area, RecordID, ErrorDescription, Status, Checklist, Additional_Comments)
SELECT 
	'Agreement', 
	a.AgreementID,
	CASE WHEN v.AgreementCodeValidationID IS NULL THEN 'Invalid combination of AgreementClassCode, AgreementTypeCode, AgreementRightsTypeCode, and AgreementTractStatusCode' END AS ErrorDescription,
	CASE WHEN v.AgreementCodeValidationID IS NULL THEN 'FAIL' ELSE 'PASS' END AS Status,
	'Check to ensure that class type, agreement type, and rights type codes are present and show in the UI',
	'If the combination is not in the validation (along with tract status), the field will be populated in the database and reports, but the UI will be empty'
FROM Agreement a
	JOIN AgreementTract t ON a.AgreementID = t.AgreementID
	LEFT JOIN AgreementCodeValidation v
		ON a.AgreementClassCode = v.AgreementClassCode 
		AND a.AgreementTypeCode = v.AgreementTypeCode 
		AND a.AgreementRightsTypeCode = v.AgreementRightsTypeCode 
		AND t.AgreementTractStatusCode = v.AgreementTractStatusCode
;
--#endregion: Agreement
--#region: AgreementTract
--Ensure every Agreement Tract is tied to a Area
INSERT INTO #QC_Log (Area, RecordID, ErrorDescription, Status, Checklist, Additional_Comments)
SELECT 
	'AgreementTract', 
	AgreementTractID,
	CASE WHEN AreaID IS NULL THEN 'AgreementTract is not tied to an Area (AreaID is missing)' ELSE 'PASS' END AS ErrorDescription,
	CASE WHEN AreaID IS NULL THEN 'FAIL' ELSE 'PASS' END AS Status,
	'Ensure every Agreement Tract is tied to an Area',
	'Every agreement tract must have a Unit and every Unit must have a team'
FROM AgreementTract;
--Ensure acreage fields are populated (also be sure to confirm that report gross is populated too)
INSERT INTO #QC_Log (Area, RecordID, ErrorDescription, Status, Checklist, Additional_Comments)
SELECT 
	'AgreementTract',
	AgreementTractID,
	CASE 
		WHEN GrossAcres IS NOT NULL AND GrossReportedAcres IS NOT NULL AND FirstPartyNetAcresCalc IS NOT NULL
			AND GroupNetAcresCalc IS NOT NULL AND CompanyNetAcresCalc IS NOT NULL AND CompanyNRIACalc IS NOT NULL 
			AND ResponsibleNetAcresCalc IS NOT NULL AND NetMineralAcresCalc IS NOT NULL
			THEN 'PASS'
		ELSE NULLIF(CONCAT(
			CASE WHEN GrossAcres IS NULL THEN 'GrossAcres is missing; ' ELSE '' END,
			CASE WHEN GrossReportedAcres IS NULL THEN 'GrossReportedAcres is missing; ' ELSE '' END,
			CASE WHEN FirstPartyNetAcresCalc IS NULL THEN 'FirstPartyNetAcresCalc is missing; ' ELSE '' END,
			CASE WHEN GroupNetAcresCalc IS NULL THEN 'GroupNetAcresCalc is missing; ' ELSE '' END,
			CASE WHEN CompanyNetAcresCalc IS NULL THEN 'CompanyNetAcresCalc is missing; ' ELSE '' END,
			CASE WHEN CompanyNRIACalc IS NULL THEN 'CompanyNRIACalc is missing; ' ELSE '' END,
			CASE WHEN ResponsibleNetAcresCalc IS NULL THEN 'ResponsibleNetAcresCalc is missing; ' ELSE '' END,
			CASE WHEN NetMineralAcresCalc IS NULL THEN 'NetMineralAcresCalc is missing; ' ELSE '' END
		),'') 
	END AS ErrorDescription,
	CASE 
		WHEN GrossAcres IS NULL OR GrossReportedAcres IS NULL OR FirstPartyNetAcresCalc IS NULL 
			OR GroupNetAcresCalc IS NULL OR CompanyNetAcresCalc IS NULL OR CompanyNRIACalc IS NULL 
			OR ResponsibleNetAcresCalc IS NULL OR NetMineralAcresCalc IS NULL 
			THEN 'FAIL'
		ELSE 'PASS'
	END AS Status,
	'Ensure acreage fields are populated (also be sure to confirm that report gross is populated too)',
	NULL
FROM AgreementTract; 
--Check to make sure that net < Gross and CoNet < Net
INSERT INTO #QC_Log (Area, RecordID, ErrorDescription, Status, Checklist, Additional_Comments)
SELECT 
	'AgreementTract',
	AgreementTractID,
	CASE 
		WHEN ISNULL(NetMineralAcresCalc,0) > ISNULL(GrossAcres,0) THEN 'NetMineralAcresCalc is greater than GrossAcres' 
		WHEN ISNULL(FirstPartyNetAcresCalc,0) > ISNULL(GrossAcres,0) THEN 'FirstPartyNetAcresCalc is greater than GrossAcres'
		WHEN ISNULL(CompanyNetAcresCalc,0) > ISNULL(NetMineralAcresCalc,0) THEN 'CompanyNetAcresCalc is greater than NetMineralAcresCalc'
		ELSE 'PASS'
	END AS ErrorDescription,
	CASE 
		WHEN ISNULL(NetMineralAcresCalc,0) <= ISNULL(GrossAcres,0) AND ISNULL(FirstPartyNetAcresCalc,0) <= ISNULL(GrossAcres,0)
			AND ISNULL(CompanyNetAcresCalc,0) <= ISNULL(NetMineralAcresCalc,0) THEN 'PASS'
		ELSE 'FAIL'
	END AS Status,
	'Check to make sure that net < Gross and CoNet < Net',
	'If more, then error in tract doi'
FROM AgreementTract;
--Confirm formations are populated
INSERT INTO #QC_Log (Area, RecordID, ErrorDescription, Status, Checklist, Additional_Comments)
SELECT 
	'AgreementTract', 
	AgreementTractID, 
	CASE 
		WHEN FormationFromCalc IS NULL OR FormationToCalc IS NULL OR FormationsCalc IS NULL THEN 
			CONCAT(
				CASE WHEN FormationFromCalc IS NULL THEN 'FormationsFromCalc is missing; ' ELSE '' END,
				CASE WHEN FormationToCalc IS NULL THEN 'FormationsToCalc is missing; ' ELSE '' END,
				CASE WHEN FormationsCalc IS NULL THEN 'FormationsCalc is missing; ' ELSE '' END
			)
		ELSE 'PASS' 
	END AS ErrorDescription,
	CASE 
		WHEN FormationFromCalc IS NULL OR FormationToCalc IS NULL OR FormationsCalc IS NULL THEN 'FAIL'
		ELSE 'PASS'
	END AS Status,
	'Confirm formations are populated', 
	'Could be specific formations, or Unverified (* to BSMT)'
FROM AgreementTract;
--Validate tract map references against the legal matrix
INSERT INTO #QC_Log (Area, RecordID, ErrorDescription, Status, Checklist, Additional_Comments)
	SELECT 
	'AgreementTract', 
	AgreementTractID, 
	CASE WHEN LVLandgridID IS NULL THEN 'Map references are inconsistent with the legal matrix' ELSE 'PASS' END,
	CASE WHEN LVLandgridID IS NULL THEN 'FAIL' ELSE 'PASS' END,
	'Validate tract map references against the legal matrix',
	'Confirm if client is using their own legal matrix and compare against that (would most likely be Texas Legals)'
FROM AgreementTract t
	LEFT JOIN LVLandgrid lg 
	ON COALESCE(t.StateAbbr, 'NULL') = COALESCE(lg.StateAbbr, 'NULL')
	AND COALESCE(t.County, 'NULL') = COALESCE(lg.County, 'NULL')
	AND COALESCE(t.TWP, 0) = COALESCE(lg.TWP, 0)
	AND COALESCE(t.TWPDIR, 'NULL') = COALESCE(lg.TWPDIR, 'NULL')
	AND COALESCE(t.RNG, 0) = COALESCE(lg.RNG, 0)
	AND COALESCE(t.SEC, 'NULL') = COALESCE(lg.SEC, 'NULL')
	AND COALESCE(t.Survey, 'NULL') = COALESCE(lg.Survey, 'NULL')
	AND COALESCE(t.Abstract, 'NULL') = COALESCE(lg.Abstract, 'NULL')
	AND COALESCE(t.[Block], 'NULL') = COALESCE(lg.[Block], 'NULL')
	AND COALESCE(t.ParcelID, 'NULL') = COALESCE(lg.ParcelID, 'NULL')
;
--#endregion: AgreementTract
--#region: AgreementTractDOI
--Ensure each tract has at least a lessor and company interest
INSERT INTO #QC_Log (Area, RecordID, ErrorDescription, Status, Checklist, Additional_Comments)
SELECT 
	'AgreementTract', 
	t.AgreementTractID, 
	CASE 
		WHEN d1.AgreementTractDOIID IS NULL THEN 'No LESSOR entry for this AgreementTract'
		WHEN d2.AgreementTractDOIID IS NULL THEN 'No CompanyInt entry for this AgreementTract'
		ELSE 'PASS'
	END AS ErrorDescription,
	CASE 
		WHEN d1.AgreementTractDOIID IS NULL OR d2.AgreementTractDOIID IS NULL THEN 'FAIL'
		ELSE 'PASS'
	END AS Status,
	'Ensure each tract has at least a lessor and company interest',
	NULL AS Additional_Comments
FROM 
    AgreementTract t
		LEFT JOIN (
			SELECT AgreementTractID, AgreementTractDOIID 
			FROM AgreementTractDOI 
			WHERE AgreementTractDOIInterestTypeCode = 'LESSOR'
		) d1 ON t.AgreementTractID = d1.AgreementTractID
		LEFT JOIN (
			SELECT AgreementTractID, AgreementTractDOIID 
			FROM AgreementTractDOI 
			WHERE CompanyInt = 1
		) d2 ON t.AgreementTractID = d2.AgreementTractID
;
--Confirm interest types match the agreement type/rights type/tract status
INSERT INTO #QC_Log (Area, RecordID, ErrorDescription, Status, Checklist, Additional_Comments)
SELECT DISTINCT --a.AgreementID, AgreementTractNumber, S.AgreementTractStatusCategoryCode, CompanyInt,
	'AgreementTractDOI', 
	d.AgreementTractDOIID,
	CASE
		WHEN s.AgreementTractStatusCategoryCode = 'ORRI' AND AgreementTractDOIInterestTypeCode = 'ORRI' 
			THEN CONCAT(CAST(a.AgreementID AS varchar), '-', CAST(t.AgreementTractNumber AS varchar), ': Bad combination of tract status category and interest type (', d.AgreementTractDOIInterestTypeCode, ' should be COORRI)')
		WHEN s.AgreementTractStatusCategoryCode = 'NPRI' AND AgreementTractDOIInterestTypeCode = 'NPRI'
			THEN CONCAT(CAST(a.AgreementID AS varchar), '-', CAST(t.AgreementTractNumber AS varchar), ': Bad combination of tract status category and interest type (', d.AgreementTractDOIInterestTypeCode, ' should be NPRI)')
		WHEN (s.AgreementTractStatusCategoryCode = 'MIN' OR s.AgreementTractStatusCategoryCode = 'PARTMIN') AND AgreementTractDOIInterestTypeCode = 'MIN'
			THEN CONCAT(CAST(a.AgreementID AS varchar), '-', CAST(t.AgreementTractNumber AS varchar), ': Bad combination of tract status category and interest type (', d.AgreementTractDOIInterestTypeCode, ' should be COMIN)')
		ELSE 'PASS'
	END AS ErrorDescription,
	CASE 
		WHEN (s.AgreementTractStatusCategoryCode = 'ORRI' AND AgreementTractDOIInterestTypeCode = 'ORRI')
			OR (s.AgreementTractStatusCategoryCode = 'NPRI' AND AgreementTractDOIInterestTypeCode = 'NPRI')
			OR ((s.AgreementTractStatusCategoryCode = 'MIN' OR s.AgreementTractStatusCategoryCode = 'PARTMIN') AND AgreementTractDOIInterestTypeCode = 'MIN')
			THEN 'FAIL' 
		ELSE 'PASS'
	END AS Status,
	'Confirm interest types match the agreement type/rights type/tract status',
	'ORRI tract will need a COORRI interest type, PR will need GWI, etc.' AS Additional_Comments
FROM AgreementTractDOI d
	JOIN AgreementTract t ON d.AgreementTractID = t.AgreementTractID
	JOIN Agreement a ON t.AgreementID = a.AgreementID
	JOIN AgreementTractStatus s ON t.AgreementTractStatusCode = s.AgreementTractStatusCode
WHERE CompanyInt = 1
;
--Ensure BillingDecimal, ConveyedDecimal, and OwnerNumber are populated
INSERT INTO #QC_Log (Area, RecordID, ErrorDescription, Status, Checklist, Additional_Comments)
SELECT 
	'AgreementTractDOI',
	AgreementTractDOIID, 
	CASE WHEN BillingDecimal IS NULL THEN 'BillingDecimal not populated' ELSE 'PASS' END, 
	CASE WHEN BillingDecimal IS NULL THEN 'FAIL' ELSE 'PASS' END,
	'Ensure the Billing Interest is populated',
	'If we don''t get the Billing Interest from the client, default to the Interest Decimal'
FROM AgreementTractDOI
UNION
SELECT
	'AgreementTractDOI',
	AgreementTractDOIID, 
	CASE WHEN ConveyedDecimal IS NULL THEN 'ConveyedDecimal not populated' ELSE 'PASS' END,
	CASE WHEN ConveyedDecimal IS NULL THEN 'FAIL' ELSE 'PASS' END,
	'Ensure Conveyed Decimal is populated',
	'Unless we get something different from the client, this will mostly always be 1.0'
FROM AgreementTractDOI
UNION
SELECT
	'AgreementTractDOI',
	AgreementTractDOIID, 
	CASE WHEN OwnerNumber IS NULL AND OwnerName NOT IN ('ROYALTY RATE', 'OVERRIDE BURDEN') THEN 'OwnerNumber not populated' ELSE 'PASS' END,
	CASE WHEN OwnerNumber IS NULL AND OwnerName NOT IN ('ROYALTY RATE', 'OVERRIDE BURDEN') THEN 'FAIL' ELSE 'PASS' END,
	'Ensure Owner Number is populated, if applicable',
	NULL
FROM AgreementTractDOI;
--For Company Interest, make sure the Owner Name is populated with the Company Code from the Company Table
INSERT INTO #QC_Log (Area, RecordID, ErrorDescription, Status, Checklist, Additional_Comments)
SELECT
	'AgreementTractDOI',
	d.AgreementTractDOIID, 
	CASE WHEN c.CompanyID IS NULL THEN 'OwnerName does not match any CompanyCode in the Company table' ELSE 'PASS' END, 
	CASE WHEN c.CompanyID IS NULL THEN 'FAIL' ELSE 'PASS' END,
	'For Company Interest, make sure the Owner Name is populated with the Company Code from the Company Table',
	NULL
FROM AgreementTractDOI d
	LEFT JOIN Company c ON d.OwnerName = c.CompanyCode
WHERE d.CompanyInt = 1;
--#endregion: AgreementTractDOI
--#region: AgreementProvision
INSERT INTO #QC_Log (Area, RecordID, ErrorDescription, Status, Checklist, Additional_Comments)
--Ensure all have a YES or NO populated
SELECT
	'AgreementProvision', 
	AgreementProvisionID, 
	CASE WHEN YesNo IS NULL THEN 'YesNo field is not populated' ELSE 'PASS' END, 
	CASE WHEN YesNo IS NULL THEN 'FAIL' ELSE 'PASS' END,
	'Ensure all have a YES or NO populated',
	NULL
FROM AgreementProvision
UNION 
--Ensure that payment and obligations have first/last call dates with frequencies populated 
SELECT
	'AgreementProvision',
	AgreementProvisionID,
	CASE
		WHEN (FirstCallDate IS NOT NULL AND LastCallDate IS NOT NULL AND Frequency IS NOT NULL AND FrequencyUnit IS NOT NULL) THEN 'PASS'
		ELSE NULLIF(CONCAT(
			CASE WHEN FirstCallDate IS NULL THEN 'FirstCallDate is missing; ' ELSE '' END,
			CASE WHEN LastCallDate IS NULL THEN 'LastCallDate is missing; ' ELSE '' END,
			CASE WHEN Frequency IS NULL THEN 'Frequency is missing; ' ELSE '' END,
			CASE WHEN FrequencyUnit IS NULL THEN 'FrequencyUnit is missing; ' ELSE '' END
		),'') 
	END AS ErrorDescription, 
	CASE WHEN (FirstCallDate IS NULL OR LastCallDate IS NULL OR Frequency IS NULL OR FrequencyUnit IS NULL) THEN 'FAIL' ELSE 'PASS' END,
	'Ensure that payment and obligations have first/last call dates with frequencies populated',
	NULL
FROM AgreementProvision
WHERE AgreementProvisionTypeCode IN ('BN', 'COMPROY', 'DBN', 'DRILL', 'EXT', 'MIN', 'MR', 'P1', 'RA', 'RN', 'ROWPAY', 
									 'ROY', 'SI', 'SPF', 'SUR', 'SURPAY', 'SURPAYWELL', 'MSPT')
UNION 
--Check to make sure all payments have a payment amount populated
SELECT --AgreementID, AgreementProvisionTypeCode,
	'AgreementProvision', 
	AgreementProvisionID,
	CASE WHEN ProvisionAmount IS NULL THEN 'AgreementProvisionTypeCode has no ProvisionAmount populated for a payment' ELSE 'PASS' END,
	CASE WHEN ProvisionAmount IS NULL THEN 'FAIL' ELSE 'PASS' END,
	'Check to make sure all payments have a payment amount populated',
	NULL
FROM AgreementProvision
WHERE AgreementProvisionTypeCode IN ('BN', 'COMPROY', 'DBN', 'DRILL', 'EXT', 'MIN', 'MR', 'P1', 'RA', 'RN', 'ROWPAY', 
                                     'ROY', 'SI', 'SPF', 'SUR', 'SURPAY', 'SURPAYWELL', 'MSPT')
;
INSERT INTO #QC_Log (Area, RecordID, ErrorDescription, Status, Checklist, Additional_Comments)
--Ensure payment provisions have at least one payee associated 
SELECT  
	'AgreementProvision', 
	p.AgreementProvisionID, 
	CASE WHEN AgreementPayeeID IS NULL THEN 'No associated record in AgreementPayee for payment provision' ELSE 'PASS' END, 
	CASE WHEN AgreementPayeeID IS NULL THEN 'FAIL' ELSE 'PASS' END,
	'Ensure payment provisions have at least one payee associated',
	NULL
FROM AgreementProvision p
	LEFT JOIN AgreementPayee ap ON p.AgreementProvisionID = ap.AgreementProvisionID
WHERE p.AgreementProvisionTypeCode IN ('BN', 'COMPROY', 'DBN', 'DRILL', 'EXT', 'MIN', 'MR', 'P1', 'RA', 'RN', 'ROWPAY', 'ROY', 'SI', 'SPF', 'SUR', 'SURPAY', 'SURPAYWELL', 'MSPT')
--Ensure all payees total = provision amount
SELECT  
	'AgreementProvision', 
	p.AgreementProvisionID,
	CASE WHEN p.ProvisionAmount <> ap.TotalPayeeAmount THEN 'Sum of PayeeAmount does not equal ProvisionAmount' ELSE 'PASS' END,
	CASE WHEN p.ProvisionAmount <> ap.TotalPayeeAmount THEN 'FAIL' ELSE 'PASS' END,
	'Ensure all payees total = provision amount',
	NULL
FROM AgreementProvision p
	JOIN (
		SELECT AgreementProvisionID, SUM(PayeeAmount) AS TotalPayeeAmount
		FROM AgreementPayee
		GROUP BY AgreementProvisionID
	) ap ON p.AgreementProvisionID = ap.AgreementProvisionID
UNION
--Ensure Paid By is populated
SELECT 
	'AgreementProvision',
	AgreementProvisionID,
	CASE WHEN AgreementPaidByCode IS NULL THEN 'AgreementPaidByCode is missing' ELSE 'PASS' END,
	CASE WHEN AgreementPaidByCode IS NULL THEN 'FAIL' ELSE 'PASS' END,
	'Ensure Paid By is populated',
	'Need to confirm with client what they want this defaulted to if they don''t have this in their source data'
FROM AgreementProvision
UNION
--Ensure Bill To is populated and the corresponding Number is populated
SELECT 
	'AgreementProvision', 
	p.AgreementProvisionID, 
	CASE WHEN AgreementProvisionBillToID IS NULL THEN 'No associated record in AgreementProvisionBillTo' ELSE 'PASS' END, 
	CASE WHEN AgreementProvisionBillToID IS NULL THEN 'FAIL' ELSE 'PASS' END, 
	'Ensure Bill To is populated and the corresponding Number is populated', 
	'Need to confirm with client what they want this defaulted to if they don''t have this in their source data; or we need to ''allow'' missing values here in the configuration table'
FROM AgreementProvision p
	LEFT JOIN AgreementProvisionBillTo b ON b.AgreementProvisionID = p.AgreementProvisionID
UNION
--Ensure JIB Category is populated
SELECT 
	'AgreementProvision', 
	AgreementProvisionID, 
	CASE WHEN AgreementJIBCategoryCode IS NULL THEN 'AgreementJIBCategoryCode is missing' ELSE 'PASS' END, 
	CASE WHEN AgreementJIBCategoryCode IS NULL THEN 'FAIL' ELSE 'PASS' END,
	'Ensure JIB Category is populated',
	'Need to confirm with client what they want this defaulted to if they don''t have this in their source data; or we need to ''allow'' missing values here in the configuration table'
FROM AgreementProvision;
--#endregion: AgreementProvision
--#region: AgreementPayee
--IF possible, confirm that payee has owner number from owner table loaded
INSERT INTO #QC_Log (Area, RecordID, ErrorDescription, Status, Checklist, Additional_Comments)
SELECT 
	'AgreementPayee',
	p.AgreementPayeeID, 
	CASE WHEN o.OwnerNumber IS NULL THEN 'OwnerNumber does not match any OwnerNumber in the Owner table' ELSE 'PASS' END,
	CASE WHEN o.OwnerNumber IS NULL THEN 'FAIL' ELSE 'PASS' END,
	'IF possible, confirm that payee has owner number from owner table loaded',
	'The Owner has to be an active Owner; if we don''t have this data, then we need to ''allow'' missing values here in the configuration table'
FROM AgreementPayee p
	LEFT JOIN [Owner] o ON p.OwnerNumber = o.OwnerNumber
UNION
--Ensure Payment Method is populated
SELECT 
	'AgreementPayee', 
	AgreementPayeeID, 
	CASE WHEN  PaymentMethodCode IS NULL THEN 'PaymentMethodCode is missing' ELSE 'PASS' END, 
	CASE WHEN  PaymentMethodCode IS NULL THEN 'FAIL' ELSE 'PASS' END,
	'Ensure Payment Method is populated',
	'Need to confirm with client what they want this defaulted to if they don''t have this in their source data'
FROM AgreementPayee;
--#endregion: AgreementPayee
--#region: AreaGeoBasin
--Ensure at least one geobasin is set up 
INSERT INTO #QC_Log (Area, RecordID, ErrorDescription, Status, Checklist, Additional_Comments)
SELECT 
	'AreaGeoBasin', 
	NULL AS RecordID,
	CASE WHEN NOT EXISTS (SELECT 1 FROM AreaGeoBasin) THEN 'AreaGeoBasin table has no records' ELSE 'PASS' END AS ErrorDescription,
	CASE WHEN NOT EXISTS (SELECT 1 FROM AreaGeoBasin) THEN 'FAIL' ELSE 'PASS' END AS Status,
	'Ensure at least one geobasin is set up' AS Checklist,
	NULL AS Additional_Comments
;
--Ensure geobasin has formations 
INSERT INTO #QC_Log (Area, RecordID, ErrorDescription, Status, Checklist, Additional_Comments)
SELECT 
	'AreaGeoBasin', 
	b.AreaGeoBasinID, 
	CASE WHEN AreaGeoBasinFormationID IS NULL THEN 'No associated record in AreaGeoBasinFormation' ELSE 'PASS' END, 
	CASE WHEN AreaGeoBasinFormationID IS NULL THEN 'FAIL' ELSE 'PASS' END, 
	'Ensure geobasin has formations', 
	NULL
FROM AreaGeoBasin b
	LEFT JOIN AreaGeoBasinFormation f ON f.AreaGeoBasinID = b.AreaGeoBasinID
;
--#endregion: AreaGeoBasin
--#region: AreaHierarchy
--Confirm at least one prospect/hierarchy is loaded
INSERT INTO #QC_Log (Area, RecordID, ErrorDescription, Status, Checklist, Additional_Comments)
SELECT 
	'AreaHierarchy', 
	NULL, 
	CASE WHEN NOT EXISTS (SELECT 1 FROM AreaHierarchy) THEN 'AreaHierarchy table is empty' ELSE 'PASS' END,
	CASE WHEN NOT EXISTS (SELECT 1 FROM AreaHierarchy) THEN 'FAIL' ELSE 'PASS' END,
	'Confirm at least one prospect/hierarchy is loaded', 
	NULL
;
--Confirm all records are tied to a geo basin 
INSERT INTO #QC_Log (Area, RecordID, ErrorDescription, Status, Checklist, Additional_Comments)
SELECT 
	'AreaHierarchy', 
	AreaHierarchyID,
	CASE WHEN AreaGeoBasinID IS NULL THEN 'GeoBasin is missing' ELSE 'PASS' END,
	CASE WHEN AreaGeoBasinID IS NULL THEN 'FAIL' ELSE 'PASS' END, 
	'Confirm all records are tied to a geo basin', 
	NULL
FROM AreaHierarchy;
--#endregion: AreaHierarchy
--#region: Area (header)
--Ensure every Unit has a Team assigned
INSERT INTO #QC_Log (Area, RecordID, ErrorDescription, Status, Checklist, Additional_Comments)
SELECT 
	'Area', 
	a.AreaID,
	CASE WHEN t.AreaTeamID IS NULL THEN 'Areas are missing from AreaTeam' ELSE 'PASS' END,
	CASE WHEN t.AreaTeamID IS NULL THEN 'FAIL' ELSE 'PASS' END,
	'Ensure every Unit has a Team assigned',
	'Every agreement tract must have a Unit and every Unit must have a team'
FROM Area a
	LEFT JOIN AreaTeam t ON a.AreaID = t.AreaID
;
--Confirm all units have a hierarchy tied to them
INSERT INTO #QC_Log (Area, RecordID, ErrorDescription, Status, Checklist, Additional_Comments)
SELECT 
	'Area', 
	AreaID, 
	CASE WHEN AreaHierarchyID IS NULL THEN 'AreaHierarchyID is missing' ELSE 'PASS' END,
	CASE WHEN AreaHierarchyID IS NULL THEN 'FAIL' ELSE 'PASS' END, 
	'Confirm all units have a hierarchy tied to them', 
	NULL
FROM Area
UNION
--Confirm unit name, legal, and description are all populated
SELECT 
	'Area', 
	AreaID,
	CASE 
		WHEN AreaName IS NOT NULL AND AreaLegal IS NOT NULL AND AreaDescription IS NOT NULL THEN 'PASS'
		ELSE NULLIF(CONCAT(
			CASE WHEN AreaName IS NULL THEN 'AreaName is NULL; ' ELSE '' END,
			CASE WHEN AreaLegal IS NULL THEN 'AreaLegal is NULL; ' ELSE '' END,
			CASE WHEN AreaDescription IS NULL THEN 'AreaDescription is missing; ' ELSE '' END
		),'') 
	END AS ErrorDescription,
    CASE WHEN AreaName IS NULL OR AreaLegal IS NULL OR AreaDescription IS NULL THEN 'FAIL' ELSE 'PASS' END,
	'Confirm unit name, legal, and description are all populated',
	NULL
FROM Area;
--#endregion: Area (header)
--#region: AreaTract
--Ensure tracts are loaded and populated with necessary information 
--Legal, state/county, usually set allocation to 100
INSERT INTO #QC_Log (Area, RecordID, ErrorDescription, Status, Checklist, Additional_Comments)
SELECT  
	'Area', 
	a.AreaID, 
	CASE WHEN t.AreaID IS NULL THEN 'No associated record in AreaTract' ELSE 'PASS' END, 
	CASE WHEN t.AreaID IS NULL THEN 'FAIL' ELSE 'PASS' END,
	'Ensure tracts are loaded and populated with necessary information',
	'Legal, state/county, usually set allocation to 100'
FROM Area a
	LEFT JOIN AreaTract t ON t.AreaID = a.AreaID
UNION
SELECT 
	'AreaTract', 
	AreaTractID,
	CASE 
		WHEN StateAbbr IS NOT NULL AND County IS NOT NULL AND TractLegal IS NOT NULL AND AllocationFactor IS NOT NULL THEN 'PASS'
		ELSE NULLIF(CONCAT(
			CASE WHEN StateAbbr IS NULL THEN 'StateAbbr is missing; ' ELSE '' END,
			CASE WHEN County IS NULL THEN 'County is missing; ' ELSE '' END,
			CASE WHEN TractLegal IS NULL THEN 'TractLegal is missing; ' ELSE '' END,
			CASE WHEN AllocationFactor IS NULL THEN 'AllocationFactor is missing; ' ELSE '' END
		),'') 
	END AS ErrorDescription,
    CASE WHEN StateAbbr IS NULL OR County IS NULL OR TractLegal IS NULL OR AllocationFactor IS NULL THEN 'FAIL' ELSE 'PASS' END,
	'Ensure tracts are loaded and populated with necessary information',
	'Legal, state/county, usually set allocation to 100'
FROM AreaTract;
--#endregion: AreaTract
--#region: Asset (header)
--Ensure all asset data is loaded correctly
--AssetName, AssetClassCode, AssetTypeCode, AssetStatusCode, AreaID
INSERT INTO #QC_Log (Area, RecordID, ErrorDescription, Status, Checklist, Additional_Comments)
SELECT
	'Asset', 
	AssetID,
	CASE
		WHEN AssetName IS NOT NULL AND AssetClassCode IS NOT NULL AND AssetTypeCode IS NOT NULL AND AssetStatusCode IS NOT NULL AND AreaID IS NOT NULL THEN 'PASS'
		ELSE NULLIF(CONCAT(
			CASE WHEN AssetName IS NULL THEN 'AssetName is missing; ' ELSE '' END,
			CASE WHEN AssetClassCode IS NULL THEN 'AssetClassCode is missing; ' ELSE '' END,
			CASE WHEN AssetTypeCode IS NULL THEN 'AssetTypeCode is missing; ' ELSE '' END,
			CASE WHEN AssetStatusCode IS NULL THEN 'AssetStatusCode is missing; ' ELSE '' END,
			CASE WHEN AreaID IS NULL THEN 'AreaID is missing; ' ELSE '' END
		),'')
	END AS ErrorDescription,
    CASE WHEN AssetName IS NULL OR AssetClassCode IS NULL OR AssetTypeCode IS NULL OR AssetStatusCode IS NULL OR AreaID IS NULL THEN 'FAIL' ELSE 'PASS' END,
	'Ensure all asset data is loaded correctly',
	'AssetName, AssetClassCode, AssetTypeCode, AssetStatusCode, AreaID'
FROM Asset;
--Check to confirm that APIs are formatted properly 
INSERT INTO #QC_Log (Area, RecordID, ErrorDescription, Status, Checklist, Additional_Comments)
SELECT 
	'Asset', 
	AssetID, 
	CASE WHEN APINumber NOT LIKE '[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]' THEN 'Incorrect APINumber formatting' ELSE 'PASS' END, 
	CASE WHEN APINumber NOT LIKE '[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]' THEN 'FAIL' ELSE 'PASS' END, 
	'Check to confirm that APIs are formatted properly',
	NULL
FROM Asset
;
--Confirm asset header interests are not exceeding 100%
INSERT INTO #QC_Log (Area, RecordID, ErrorDescription, Status, Checklist, Additional_Comments)
SELECT  
	'Asset', 
	AssetID, 
	CASE WHEN (ISNULL(WICalc, 0) + ISNULL(ORRICalc, 0) + ISNULL(RICalc, 0) + ISNULL(NRIOILCalc, 0) + ISNULL(NRIGasCalc, 0)) > 100 THEN 'Sum of interest values exceeds 100%' ELSE 'PASS' END, 
	CASE WHEN (ISNULL(WICalc, 0) + ISNULL(ORRICalc, 0) + ISNULL(RICalc, 0) + ISNULL(NRIOILCalc, 0) + ISNULL(NRIGasCalc, 0)) > 100 THEN 'FAIL' ELSE 'PASS' END,
	'Confirm asset header interests are not exceeding 100%',
	'Default is to use the Well Interest, but some clients want to use the Accounting DOI interest if there is an integration'
FROM Asset
UNION
--Confirm all Assets are indexed to an Area
SELECT  
	'Asset', 
	a.AssetID, 
	CASE WHEN t.AreaID IS NULL THEN 'Indexed Area is missing' ELSE 'PASS' END, 
	CASE WHEN t.AreaID IS NULL THEN 'FAIL' ELSE 'PASS' END,
	'Confirm all Assets are indexed to an Area',
	NULL
FROM Asset a
	LEFT JOIN Area t ON t.AreaID = a.AreaID
;
--#endregion: Asset (header)
--#region: AssetTract
INSERT INTO #QC_Log (Area, RecordID, ErrorDescription, Status, Checklist, Additional_Comments)
SELECT  
	'AssetTract', 
	AssetTractID,
	CASE 
		WHEN StateAbbr IS NOT NULL AND County IS NOT NULL AND AssetTractLegal IS NOT NULL AND AllocationFactor IS NOT NULL THEN 'PASS'
		ELSE NULLIF(CONCAT(
			CASE WHEN StateAbbr IS NULL THEN 'StateAbbr is missing; ' ELSE '' END,
			CASE WHEN County IS NULL THEN 'County is missing; ' ELSE '' END,
			CASE WHEN AssetTractLegal IS NULL THEN 'AssetTractLegal is missing; ' ELSE '' END,
			CASE WHEN AllocationFactor IS NULL THEN 'AllocationFactor is missing; ' ELSE '' END
		),'') 
	END AS ErrorDescription,
    CASE WHEN StateAbbr IS NULL OR County IS NULL OR AssetTractLegal IS NULL OR AllocationFactor IS NULL THEN 'FAIL' ELSE 'PASS' END,
	'Ensure wells have tracts and necessary information is populated',
	NULL
FROM AssetTract
UNION
--Log duplicate AssetTract records
SELECT 
	'AssetTract', 
	MIN(AssetTractID) AS RecordID,
	CASE WHEN COUNT(*) > 1 THEN 'Duplicate records found in AssetTract' ELSE 'PASS' END AS ErrorDescription,
	CASE WHEN COUNT(*) > 1 THEN 'FAIL' ELSE 'PASS' END AS Status,
	'Confirm no duplicate tracts' AS Checklist,
	NULL AS Additional_Comments
FROM AssetTract
GROUP BY ISNULL(AssetID, -1), ISNULL(StateAbbr, ''), ISNULL(County, ''), ISNULL(TWP, ''), ISNULL(TWPDIR, ''), ISNULL(RNG, ''), 
	ISNULL(RNGDIR, ''), ISNULL(SEC, ''), ISNULL([Block], ''), ISNULL(Abstract, ''), ISNULL(Survey, ''), ISNULL(Quartering, ''), ISNULL(AssetTractLegal, ''), ISNULL(Lot, '')
;
--#endregion: AssetTract
--#region: AssetInterest
--Ensure well interest is populated with company interests if applicable
INSERT INTO #QC_Log (Area, RecordID, ErrorDescription, Status, Checklist, Additional_Comments)
SELECT 
	'AssetInterest', 
	AssetInterestID,
	CASE 
		WHEN WI IS NOT NULL AND ORRI IS NOT NULL AND RI IS NOT NULL AND NRIOIL IS NOT NULL AND NRIGas IS NOT NULL THEN 'PASS'
		ELSE NULLIF(CONCAT(
			CASE WHEN WI IS NULL THEN 'WI is missing; ' ELSE '' END,
			CASE WHEN ORRI IS NULL THEN 'ORRI is missing; ' ELSE '' END,
			CASE WHEN RI IS NULL THEN 'RI is NULL; ' ELSE '' END,
			CASE WHEN NRIOIL IS NULL THEN 'NRIOIL is missing; ' ELSE '' END,
			 CASE WHEN NRIGas IS NULL THEN 'NRIGAS is missing; ' ELSE '' END
		),'') 
	END AS ErrorDescription,
    CASE WHEN WI IS NULL OR ORRI IS NULL OR RI IS NULL OR NRIOIL IS NULL OR NRIGas IS NULL THEN 'FAIL' ELSE 'PASS' END,
	'Ensure asset interest is populated with company interests if applicable',
	NULL
FROM AssetInterest
;
--If accounting integration, ensure well numbers match and accounting DOI is coming over
INSERT INTO #QC_Log (Area, RecordID, ErrorDescription, Status, Checklist, Additional_Comments)
SELECT 
	'AssetInterest', 
	NULL,
	CASE WHEN NOT EXISTS (SELECT 1 FROM etl.Acctg_WELL_Data) THEN 'etl.Acctg_WELL_Data is empty; follow up with client' END,
	CASE WHEN NOT EXISTS (SELECT 1 FROM etl.Acctg_WELL_Data) THEN 'CHECK' ELSE 'PASS' END, 
	'If accounting integration, ensure well numbers match and accounting DOI is coming over',
	NULL
UNION
SELECT 
	'Asset', 
	w.AssetID,
	CASE 
		WHEN ew.WellNumber IS NOT NULL AND w.AssetNumber IS NOT NULL
			AND COALESCE(WI, 0) = COALESCE(WICalc, 0) 
			AND COALESCE(ORRI, 0) = COALESCE(ORRICalc, 0) 
			AND COALESCE(RI, 0) = COALESCE(RICalc, 0) 
			AND COALESCE(NRIOIL, 0) = COALESCE(NRIOILCalc, 0) 
			AND COALESCE(NRIGas, 0) = COALESCE(NRIGasCalc, 0) 
			AND COALESCE(APO_WI, 0) = COALESCE(APO_WICalc, 0) 
			AND COALESCE(APO_NRI, 0) = COALESCE(APO_NRICalc, 0)
		THEN 'PASS'
		ELSE NULLIF(CONCAT(
			CASE WHEN ew.WellNumber IS NULL THEN 'Well number missing in ETL table; ' ELSE '' END,
			CASE WHEN w.AssetNumber IS NULL THEN 'Asset number missing in Asset table; ' ELSE '' END,
			CASE WHEN COALESCE(WI, 0) <> COALESCE(WICalc, 0) THEN 'Unequal WI; ' ELSE '' END,
			CASE WHEN COALESCE(ORRI, 0) <> COALESCE(ORRICalc, 0) THEN 'Unequal ORRI; ' ELSE '' END,
			CASE WHEN COALESCE(RI, 0) <> COALESCE(RICalc, 0) THEN 'Unequal RI; ' ELSE '' END,
			CASE WHEN COALESCE(NRIOIL, 0) <> COALESCE(NRIOILCalc, 0) THEN 'Unequal NRIOIL; ' ELSE '' END,
			CASE WHEN COALESCE(NRIGas, 0) <> COALESCE(NRIGasCalc, 0) THEN 'Unequal NRIGas; ' ELSE '' END,
			CASE WHEN COALESCE(APO_WI, 0) <> COALESCE(APO_WICalc, 0) THEN 'Unequal APO_WI; ' ELSE '' END,
			CASE WHEN COALESCE(APO_NRI, 0) <> COALESCE(APO_NRICalc, 0) THEN 'Unequal APO_NRI; ' ELSE '' END
		), '')
	END AS ErrorDescription,
	CASE 
		WHEN ew.WellNumber IS NULL OR w.AssetNumber IS NULL
			OR COALESCE(WI, 0) <> COALESCE(WICalc, 0) 
			OR COALESCE(ORRI, 0) <> COALESCE(ORRICalc, 0) 
			OR COALESCE(RI, 0) <> COALESCE(RICalc, 0) 
			OR COALESCE(NRIOIL, 0) <> COALESCE(NRIOILCalc, 0) 
			OR COALESCE(NRIGas, 0) <> COALESCE(NRIGasCalc, 0) 
			OR COALESCE(APO_WI, 0) <> COALESCE(APO_WICalc, 0) 
			OR COALESCE(APO_NRI, 0) <> COALESCE(APO_NRICalc, 0)
		THEN 'FAIL' 
		ELSE 'PASS' 
	END AS Status,
	'If accounting integration, ensure well numbers match and accounting DOI is coming over' AS Comments,
	NULL AS AdditionalInfo
FROM etl.Acctg_WELL_Data ew
	FULL OUTER JOIN Asset w ON ew.WellNumber = w.AssetNumber
;
--Confirm no duplicate interest lines 
INSERT INTO #QC_Log (Area, RecordID, ErrorDescription, Status, Checklist, Additional_Comments)
SELECT
	'AssetInterest', 
	MIN(AssetInterestID), 
	CASE WHEN COUNT(*) > 1 THEN 'Duplicate interest records found in AssetInteres' ELSE 'PASS' END,
	CASE WHEN COUNT(*) > 1 THEN 'FAIL' ELSE 'PASS' END,
	'Confirm no duplicate interest lines',
	'Note sometimes there could be similar lines of interest: If only a handful, may need to confirm with client this is correct - If a lot, then probably a duplication issue'
FROM AssetInterest
GROUP BY AssetID, WI, ORRI, RI, NRIOIL, NRIGas, APO_WI, APO_NRIOIL, APO_NRIGas, APO_ORI, APO_RI, BCPWI, ACPWI
;
--#endregion: AssetInterest
--#region: Document
--Confirm documents load when clicking on preview and download in the UI
INSERT INTO #QC_Log (Area, RecordID, ErrorDescription, Status, Checklist, Additional_Comments)
VALUES (
	'Document', 
	NULL, 
	'View in the UI', 
	'CHECK', 
	'Confirm documents load when clicking on preview and download in the UI', 
	'Some documents can''t be ''viewed'' without downloading (Excel, TIF)' + CHAR(10) + 'If documents are not loading, check file path is correct and that the file name is correct (DocumentID_FileName)'
)
;
--#endregion: Document
--#region: CrossReference
WITH p AS (
	SELECT *
	FROM CrossReference x
)
INSERT INTO #QC_Log (Area, RecordID, ErrorDescription, Status, Checklist, Additional_Comments)
SELECT 
	'CrossReference',
    p.CrossReferenceID AS RecordID,
	CASE 
		WHEN x.CrossReferenceID IS NOT NULL THEN 'PASS'
		ELSE CONCAT('Entity (', p.ParentTypeCode, ', ', cast(p.ParentID AS varchar(6)), ', ', ISNULL(cast(p.ParentTractID AS varchar(6)), 'NULL'), 
			   ') appears only as parent and not as child')
	END AS ErrorDescription,
    CASE WHEN x.CrossReferenceID IS NOT NULL THEN 'PASS' ELSE 'FAIL' END, 
	'Confirm cross references are both ways in the database and appear in the UI (well to agreement xref)',
	'Confirm you see the well cross referenced to the agreement/tract in the well screen' + CHAR(10) + 'Then confirm you see the agreement/tract cross referenced in the agreement screen'
FROM p
	LEFT JOIN CrossReference x
	ON p.ParentTypeCode = x.ChildTypeCode
	AND p.ParentID = x.ChildID
	AND COALESCE(p.ParentTractID, 0) = COALESCE(x.ChildTractID, 0)
	AND p.ChildTypeCode = x.ParentTypeCode
	AND p.ChildID = x.ParentID
	AND COALESCE(p.ChildTractID, 0) = COALESCE(x.ParentTractID, 0)
WHERE x.CrossReferenceID IS NULL
UNION
SELECT 
	'CrossReference',
    p.CrossReferenceID AS RecordID, 
	CASE 
		WHEN x.CrossReferenceID IS NOT NULL THEN 'PASS' 
		ELSE CONCAT('Entity (', p.ChildTypeCode, ', ', cast(p.ChildID AS varchar(6)), ', ', ISNULL(cast(p.ChildTractID AS varchar(6)), 'NULL'), 
           ') appears only as Child and not as Parent')
	END AS ErrorDescription,
    CASE WHEN x.CrossReferenceID IS NOT NULL THEN 'PASS' ELSE 'FAIL' END,
	'Confirm cross references are both ways in the database and appear in the UI (well to agreement xref)',
	'Confirm you see the well cross referenced to the agreement/tract in the well screen' + CHAR(10) + 'Then confirm you see the agreement/tract cross referenced in the agreement screen'
FROM p
	LEFT JOIN CrossReference x
	ON p.ChildTypeCode = x.ParentTypeCode
	AND p.ChildID = x.ParentID
	AND COALESCE(p.ChildTractID, 0) = COALESCE(x.ParentTractID, 0)
	AND p.ParentTypeCode = x.ChildTypeCode
	AND p.ParentID = x.ChildID
	AND COALESCE(p.ParentTractID, 0) = COALESCE(x.ChildTractID, 0)
WHERE x.CrossReferenceID IS NULL
;
--#endregion
--#region: Owner
INSERT INTO #QC_Log (Area, RecordID, ErrorDescription, Status, Checklist, Additional_Comments)
--Confirm no null owner numbers
SELECT  
	'Owner', 
	OwnerID, 
	CASE WHEN OwnerNumber IS NULL THEN 'OwnerNumber is missing' ELSE 'PASS' END, 
	CASE WHEN OwnerNumber IS NULL THEN 'FAIL' ELSE 'PASS' END,
	'Confirm no missing owner numbers',
	NULL
FROM [Owner]
UNION
--Confirm owners have an address associated with them
SELECT 
	'Owner', 
	o.OwnerID, 
	CASE WHEN a.OwnerAddressID IS NULL THEN 'Owner has no associated address in OwnerAddress' ELSE 'PASS' END, 
	CASE WHEN a.OwnerAddressID IS NULL THEN 'FAIL' ELSE 'PASS' END,
	'Confirm owners have an address associated with them',
	NULL
FROM [Owner] o
	LEFT JOIN OwnerAddress a ON o.OwnerID = a.OwnerID
UNION
--If accounting integration, confirm owners loaded correctly
SELECT
	'Owner', 
	NULL,
	CASE WHEN NOT EXISTS (SELECT 1 FROM etl.Acctg_Owner_Data) THEN 'etl.Acctg_Owner_Data is empty; follow up with client' ELSE 'PASS' END,
	CASE WHEN NOT EXISTS (SELECT 1 FROM etl.Acctg_Owner_Data) THEN 'CHECK' ELSE 'PASS' END, 
	'If accounting integration, confirm owners loaded correctly',
	'This causes issues with Payees without an owner number'
UNION
SELECT 
	'Owner', 
	OwnerID,
	CASE 
		WHEN eo.OwnerNumber IS NOT NULL AND o.OwnerNumber IS NOT NULL AND eo.OwnerName = o.OwnerName THEN 'PASS'
		ELSE NULLIF(CONCAT(
			CASE WHEN eo.OwnerNumber IS NULL THEN 'Owner missing in ETL table; ' ELSE '' END,
			CASE WHEN o.OwnerNumber IS NULL THEN 'Owner missing in Owner table; ' ELSE '' END,
			CASE WHEN eo.OwnerName <> o.OwnerName THEN 'Unequal OwnerName; ' ELSE '' END
		),'') 
	END AS ErrorDescription,
	CASE 
		WHEN eo.OwnerNumber IS NULL OR o.OwnerNumber IS NULL OR eo.OwnerName <> o.OwnerName THEN 'FAIL' ELSE 'PASS' 
	END, 
	'If accounting integration, confirm owners loaded correctly',
	'This causes issues with Payees without an owner number'
FROM etl.Acctg_Owner_Data eo
	FULL OUTER JOIN [Owner] o ON eo.OwnerNumber = o.OwnerNumber
WHERE (SELECT DISTINCT 1 FROM etl.Acctg_Owner_Data) IS NOT NULL
;
--#endregion: Owner
--#region: Tract Digit Lengths
--Ensure AgreementTractNumber, AssetTractNumber, and AreaTractNumber are exactly four digits long
INSERT INTO #QC_Log (Area, RecordID, ErrorDescription, Status, Checklist, Additional_Comments)
SELECT 
	'AgreementTract', 
	AgreementTractID, 
	CASE WHEN LEN(AgreementTractNumber) <> 4 OR AgreementTractNumber NOT LIKE '[0-9][0-9][0-9][0-9]' THEN 'AgreementTractNumber is not exactly four digits or contains non-numeric characters' ELSE 'PASS' END,
	CASE WHEN LEN(AgreementTractNumber) <> 4 OR AgreementTractNumber NOT LIKE '[0-9][0-9][0-9][0-9]' THEN 'FAIL' ELSE 'PASS' END,
	'Ensure AgreementTractNumber is exactly four digits and numeric',
	NULL
FROM AgreementTract
UNION
SELECT 
	'AssetTract', 
	AssetTractID, 
	CASE WHEN LEN(AssetTractNumber) <> 4 OR AssetTractNumber NOT LIKE '[0-9][0-9][0-9][0-9]' THEN 'AssetTractNumber is not exactly four digits or contains non-numeric characters' ELSE 'PASS' END,
	CASE WHEN LEN(AssetTractNumber) <> 4 OR AssetTractNumber NOT LIKE '[0-9][0-9][0-9][0-9]' THEN 'FAIL' ELSE 'PASS' END,
	'Ensure AssetTractNumber is exactly four digits and numeric',
	NULL
FROM AssetTract
UNION
SELECT 
    'AreaTract', 
    AreaTractID, 
    CASE WHEN LEN(AreaTractNumber) <> 4 OR AreaTractNumber NOT LIKE '[0-9][0-9][0-9][0-9]' THEN 'AreaTractNumber is not exactly four digits or contains non-numeric characters' ELSE 'PASS' END,
    CASE WHEN LEN(AreaTractNumber) <> 4 OR AreaTractNumber NOT LIKE '[0-9][0-9][0-9][0-9]' THEN 'FAIL' ELSE 'PASS' END,
    'Ensure AreaTractNumber is exactly four digits and numeric',
    NULL
FROM AreaTract
;
--#endregion: Tract Digit Lengths
--#region: QC_Log Roll-up
WITH RankedQC AS (
    SELECT 
        Area, 
        Checklist,
        Additional_Comments,
        [Reviewed - Y/N], 
        [Reviewer's Initials],
        Reviewed_Date,
        ISNULL(ErrorDescription, '') AS ErrorDescription, 
        Data_Hygienist_Comments,
        [Status],
        ROW_NUMBER() OVER (PARTITION BY Area, Checklist, Additional_Comments ORDER BY CASE WHEN ErrorDescription IS NOT NULL THEN 1 ELSE 2 END) AS rn,
        ( 
            SELECT STRING_AGG(CAST(RecordID AS VARCHAR(10)), '; ') 
            FROM (
                SELECT TOP 5 RecordID 
                FROM #QC_Log subLog
                WHERE subLog.Checklist = qclog.Checklist
                    AND [Status] = 'FAIL'
                ORDER BY RecordID
            ) AS Examples
        ) AS Example_RecordIDs
    FROM #QC_Log qclog
), fail_ct AS (
    SELECT Checklist, SUM(CASE WHEN [Status] = 'FAIL' THEN 1 ELSE 0 END) AS [Failed Record Count]
    FROM #QC_Log
    GROUP BY Checklist
), err AS (
	SELECT 
		Checklist, 
		CASE 
			WHEN MIN(ISNULL(ErrorDescription, '')) = MAX(ISNULL(ErrorDescription, '')) AND MIN(ISNULL(ErrorDescription, '')) = 'PASS' THEN 'PASS'
			ELSE (
				SELECT STRING_AGG(ISNULL(subLog.ErrorDescription, ''), CHAR(10))
				FROM (
                    SELECT ISNULL(ErrorDescription, '') AS ErrorDescription
                    FROM (
                        SELECT ErrorDescription, 
                               ROW_NUMBER() OVER (PARTITION BY ISNULL(ErrorDescription, '') ORDER BY LEN(ISNULL(ErrorDescription, '')) DESC) AS rn
                        FROM #QC_Log
                        WHERE Checklist = qclog.Checklist
                          AND ISNULL(ErrorDescription, '') <> 'PASS' -- Exclude 'PASS' in the aggregation
                    ) AS RankedErrorDescriptions
                    WHERE rn = 1 -- Ensures distinct ErrorDescriptions
                    ORDER BY LEN(ISNULL(ErrorDescription, '')) DESC
                    OFFSET 0 ROWS FETCH NEXT 5 ROWS ONLY
                ) AS subLog
            )
        END AS AggregatedErrorDescription
    FROM #QC_Log qclog
    GROUP BY Checklist
)
SELECT 
    q.Area, 
    q.Checklist, 
    q.Additional_Comments, 
    q.[Reviewed - Y/N], 
    q.[Reviewer's Initials], 
    q.Reviewed_Date, 
    NULLIF(e.AggregatedErrorDescription,'') AS [Reviewer's Comments], 
    fc.[Failed Record Count],
    q.Example_RecordIDs AS [Example_RecordIDs],
    q.Data_Hygienist_Comments
FROM RankedQC q
    JOIN fail_ct fc ON q.Checklist = fc.Checklist
    JOIN err e ON q.Checklist = e.Checklist
WHERE q.rn = 1
ORDER BY q.Area, q.Checklist;