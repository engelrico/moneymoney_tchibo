-- ---------------------------------------------------------------------------------------------------------------------
--
-- Copyright (c) 2021 Rico Engelmann
-- unofficial MoneyMoney Web Banking Extension for Tchibo
-- http://moneymoney-app.com/api/webbanking
--
--
-- The MIT License (MIT)
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
-- THE SOFTWARE.
--
-- ---------------------------------------------------------------------------------------------------------------------

WebBanking{
           version     = 1.00,
           url         = "https://www.tchibo.de/login",
           services    = {"Tchibo Mein Konto"},
           description = "Tchibo Umsätze und Kontostand"
         }

local url_login=url
local url_account="https://www.tchibo.de/account"
local url_accountstatement="https://www.tchibo.de/accountstatement"
local connection = Connection()

-- ---------------------------------------------------------------------------------------------------------------------
--localTestingStuff
-- ---------------------------------------------------------------------------------------------------------------------

local switch_localTest=false
--local url_account="/Users/xxx/Library/Containers/com.moneymoney-app.retail/Data/Library/Application Support/MoneyMoney/Extensions/account.html"
--local url_accountstatement="/Users/xxx/Library/Containers/com.moneymoney-app.retail/Data/Library/Application Support/MoneyMoney/Extensions/accountstatement.html"

local open = io.open
local function read_file(path)
    local file, err = open(path, "rb") -- r read mode and b binary mode
    if file==nil then print(err) end
  --  if not file then return nil end
    local content = file:read "*a" -- *a or *all reads the whole file
    file:close()
    return content
end
-- ---------------------------------------------------------------------------------------------------------------------
--localTestingStuff END
-- ---------------------------------------------------------------------------------------------------------------------

-- ---------------------------------------------------------------------------------------------------------------------
--parseAccountNumber
--  parse the accountNumber out of the accountPage

function parseAccountNumber(text)
  position=string.find(text, "Meine Kundennummer:")
  position_start=string.find(text,"<strong>", position)+8
  position_end=string.find(text,"</strong>", position_start)-1
  accountNumber=string.sub(text,position_start,position_end)
  return accountNumber
end

-- ---------------------------------------------------------------------------------------------------------------------
--parseOwner
--  at the moment static value
function parseOwner(text)
  return "Paule"
end

-- ---------------------------------------------------------------------------------------------------------------------
--parseBalance
--  parse the balance out of the accountstatementPage
function parseBalance(text)
  position=string.find(text, "Mein aktueller Kontostand:")
  position=string.find(text,"<strong", position)
  position_start=string.find(text,">",position)+1
  position_end=string.find(text,"€", position_start)-1
  balance=string.sub(text,position_start,position_end)
  balance=string.gsub(balance,",",".")
  return tonumber(balance)
end

function parseHiddenSubmitLink(text)
  --dirty but works
  position=string.find(text,'Wicket.Ajax.ajax')+2
  position=string.find(text,'Wicket.Ajax.ajax',position)+2
  position=string.find(text,'Wicket.Ajax.ajax',position)+23
  position_end=string.find(text,'"',position)-1
  url_hidden=string.sub(text,position,position_end)
  return url_hidden
end

-- ---------------------------------------------------------------------------------------------------------------------
--getHTML
--  depending on local_test we get the html from the web or from local file
function getHTML(url)
  local html_txt
  local html
  if switch_localTest then
    html=HTML(read_file(url))
  else
    html = HTML(connection:get(url))
  end
    html_txt=html:html()
  return html, html_txt
end

-- ---------------------------------------------------------------------------------------------------------------------
local function strToFullDate (str)
    -- Helper function for converting localized date strings to timestamps.
    local d, m, y = string.match(str, "(%d%d).(%d%d).(%d%d%d%d)")
    return os.time{year=y, month=m, day=d}
end

-- ---------------------------------------------------------------------------------------------------------------------
local function strToAmount(str)
    -- Helper function for converting localized amount strings to Lua numbers.
    local convertedValue = string.gsub(string.gsub(string.gsub(str, " .+", ""), "%.", ""), ",", ".")
    return convertedValue
end

-- ---------------------------------------------------------------------------------------------------------------------
-- ---------------------------------------------------------------------------------------------------------------------
-- MAIN PART - interfaces for MoneyMoney
-- ---------------------------------------------------------------------------------------------------------------------
function SupportsBank (protocol, bankCode)
  print("SupportsBank_tchibo")
  return protocol == ProtocolWebBanking and bankCode == "Tchibo Mein Konto"
end

-- ---------------------------------------------------------------------------------------------------------------------
function InitializeSession (protocol, bankCode, username, customer, password)
  print("InitializeSession_tchibo")
  -- Login.
  html = HTML(connection:get(url_login))
  html:xpath('//input[@id="id1"]'):attr('value', username)
  html:xpath('//input[@id="id2"]'):attr('value', password)
  --if local_test then login successful
  if switch_localTest then
    return true
  else
    html = HTML(connection:request(html:xpath('//input[@name="r:r:1:m:r:3:r:cr:1:c:pr:1:button"]'):click()))
    if html:xpath('//input[@id="id1"]'):length() > 0 then
     -- We are still at the login screen.
     return "Failed to log in. Please check your user credentials."
    end
  end
end

-- ---------------------------------------------------------------------------------------------------------------------
function ListAccounts (knownAccounts)
 print("ListAccounts")

 html,html_txt=getHTML(url_account)

  -- Return array of accounts.
  local account = {
    name = "Tchibo Mein Konto",
    owner = parseOwner(html_txt),
    accountNumber=parseAccountNumber(html_txt),
    bankCode = "012345",
    currency = "EUR",
    type = AccountTypeOther
  }
  return {account}
end


-- ---------------------------------------------------------------------------------------------------------------------
function RefreshAccount (account, since)
  local transactions = {}
  -- Return balance and array of transactions.
  local html,html_txt=getHTML(url_accountstatement)
  url_hidden=parseHiddenSubmitLink(html_txt)
  local html,html_txt=getHTML(url_hidden)

  -- Check if the HTML table with transactions exists.
    if html:xpath("//table[@class='m-tp-table m-tp-table--raw']/tbody/tr[1]/td[1]"):length() > 0 then

            -- Extract transactions.
            html:xpath("//table[@class='m-tp-table m-tp-table--raw']/tbody/tr[position()>0]"):each(function (index, row)
                local columns = row:children()
                local tmpDate=columns:get(1):text()
                local tmpAmount
                if tmpDate and string.len(tmpDate) > 0 then
                   tmpAmount=columns:get(3):text()
                  if tmpAmount == "-----" then tmpAmount=columns:get(4):text() end

                  local transaction = {
                    valueDate   = strToFullDate(tmpDate),
                    bookingDate = strToFullDate(tmpDate),
                    purpose     = columns:get(2):text(), true,
                    currency    = "EUR",
                    amount      = strToAmount(tmpAmount)
                  }
                 table.insert(transactions, transaction)
               end
            end)

    end


  return {balance=parseBalance(html_txt), transactions=transactions}
end

function EndSession ()
  -- Logout.
end
