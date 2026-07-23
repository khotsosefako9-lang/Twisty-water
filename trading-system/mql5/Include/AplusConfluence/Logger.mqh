//+------------------------------------------------------------------+
//|                                                      Logger.mqh  |
//| Journal + file logging so every decision is auditable after the  |
//| fact — required for a micro account where every trade matters.   |
//+------------------------------------------------------------------+
#property strict
#ifndef APC_LOGGER_MQH
#define APC_LOGGER_MQH

class CLogger
  {
private:
   string            m_fileName;
   int               m_fileHandle;
   bool              m_verbose;

   string TimeStampNow()
     {
      return TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS);
     }

public:
   CLogger(void) : m_fileHandle(INVALID_HANDLE), m_verbose(true) {}

   void Init(const string eaName, const bool verbose)
     {
      m_verbose = verbose;
      m_fileName = eaName + "_" + TimeToString(TimeCurrent(), TIME_DATE) + ".log";
      StringReplace(m_fileName, ".", "-");
      m_fileHandle = FileOpen(m_fileName, FILE_WRITE | FILE_READ | FILE_TXT | FILE_COMMON);
      if(m_fileHandle != INVALID_HANDLE)
         FileSeek(m_fileHandle, 0, SEEK_END);
     }

   void Write(const string tag, const string message)
     {
      string line = TimeStampNow() + " [" + tag + "] " + message;
      if(m_verbose)
         Print(line);
      if(m_fileHandle != INVALID_HANDLE)
        {
         FileWriteString(m_fileHandle, line + "\r\n");
         FileFlush(m_fileHandle);
        }
     }

   void Info(const string message)  { Write("INFO", message); }
   void Warn(const string message)  { Write("WARN", message); }
   void Error(const string message) { Write("ERROR", message); }
   void Trade(const string message) { Write("TRADE", message); }

   void Deinit(void)
     {
      if(m_fileHandle != INVALID_HANDLE)
         FileClose(m_fileHandle);
     }
  };

#endif // APC_LOGGER_MQH
