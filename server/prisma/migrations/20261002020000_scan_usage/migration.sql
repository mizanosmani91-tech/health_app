-- CreateTable
CREATE TABLE "ScanUsage" (
    "userId" TEXT NOT NULL,
    "day" TEXT NOT NULL,
    "count" INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT "ScanUsage_pkey" PRIMARY KEY ("userId","day")
);
