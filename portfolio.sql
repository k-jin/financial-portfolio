CREATE TABLE accounts (
  account_name VARCHAR2(64) NOT NULL PRIMARY KEY,
  password VARCHAR2(64) NOT NULL,
  CONSTRAINT long_password CHECK (password LIKE '________%')
);

CREATE TABLE portfolios (
  account_name VARCHAR2(64) NOT NULL CONSTRAINT account_fk REFERENCES accounts (account_name) ON DELETE CASCADE,
  portfolio_name VARCHAR2(64) NOT NULL,
  cash NUMBER NOT NULL,
  CONSTRAINT portfolio_pk PRIMARY KEY (account_name, portfolio_name)
);

CREATE TABLE stock_holdings (
  account_name VARCHAR2(64) NOT NULL,
  portfolio_name VARCHAR2(64) NOT NULL,
  symbol VARCHAR(64) NOT NULL,
  volume NUMBER NOT NULL,
  CONSTRAINT stock_holdings_fk FOREIGN KEY (account_name, portfolio_name) REFERENCES portfolios (account_name, portfolio_name) ON DELETE CASCADE,
  CONSTRAINT stock_holdings_pk PRIMARY KEY (account_name, portfolio_name, symbol)
);

CREATE TABLE stock_infos (
  symbol VARCHAR2(16) NOT NULL,
  timestamp NUMBER NOT NULL,
  open NUMBER NOT NULL,
  high NUMBER NOT NULL,
  low NUMBER NOT NULL,
  close NUMBER NOT NULL,
  volume NUMBER NOT NULL,
  CONSTRAINT stock_infos_pk PRIMARY KEY (symbol, timestamp)
);

INSERT INTO accounts VALUES('root', 'rootroot');


quit;
