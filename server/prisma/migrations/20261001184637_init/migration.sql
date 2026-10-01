-- CreateEnum
CREATE TYPE "Role" AS ENUM ('patient', 'owner');

-- CreateEnum
CREATE TYPE "PharmacyStatus" AS ENUM ('pending', 'verified', 'rejected');

-- CreateEnum
CREATE TYPE "StockStatus" AS ENUM ('in', 'low', 'out');

-- CreateEnum
CREATE TYPE "RequestStatus" AS ENUM ('new', 'replied');

-- CreateEnum
CREATE TYPE "Availability" AS ENUM ('pending', 'yes', 'no');

-- CreateEnum
CREATE TYPE "LedgerKind" AS ENUM ('income', 'expense');

-- CreateEnum
CREATE TYPE "KhataDirection" AS ENUM ('receivable', 'payable');

-- CreateTable
CREATE TABLE "User" (
    "id" TEXT NOT NULL,
    "googleSub" TEXT NOT NULL,
    "email" TEXT,
    "name" TEXT,
    "role" "Role",
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "User_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Pharmacy" (
    "id" TEXT NOT NULL,
    "ownerId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "address" TEXT NOT NULL,
    "phone" TEXT NOT NULL,
    "licenseNo" TEXT NOT NULL,
    "status" "PharmacyStatus" NOT NULL DEFAULT 'pending',
    "isOpen" BOOLEAN NOT NULL DEFAULT true,
    "openFrom" TEXT NOT NULL DEFAULT '09:00',
    "openTo" TEXT NOT NULL DEFAULT '22:00',
    "weeklyOff" TEXT,
    "notifyNew" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Pharmacy_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "LicensePhoto" (
    "pharmacyId" TEXT NOT NULL,
    "image" BYTEA NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "LicensePhoto_pkey" PRIMARY KEY ("pharmacyId")
);

-- CreateTable
CREATE TABLE "StockItem" (
    "id" TEXT NOT NULL,
    "pharmacyId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "genericName" TEXT,
    "form" TEXT,
    "qty" DECIMAL(12,2),
    "unit" TEXT,
    "buyPrice" DECIMAL(12,2),
    "sellPrice" DECIMAL(12,2),
    "expiry" TEXT,
    "batchNo" TEXT,
    "status" "StockStatus" NOT NULL DEFAULT 'in',
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "StockItem_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "MedRequest" (
    "id" TEXT NOT NULL,
    "pharmacyId" TEXT NOT NULL,
    "patientId" TEXT NOT NULL,
    "patientName" TEXT NOT NULL,
    "status" "RequestStatus" NOT NULL DEFAULT 'new',
    "replyMessage" TEXT,
    "repliedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "MedRequest_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "RequestItem" (
    "requestId" TEXT NOT NULL,
    "idx" INTEGER NOT NULL,
    "name" TEXT NOT NULL,
    "days" INTEGER NOT NULL DEFAULT 0,
    "availability" "Availability" NOT NULL DEFAULT 'pending',

    CONSTRAINT "RequestItem_pkey" PRIMARY KEY ("requestId","idx")
);

-- CreateTable
CREATE TABLE "LedgerEntry" (
    "id" TEXT NOT NULL,
    "pharmacyId" TEXT NOT NULL,
    "kind" "LedgerKind" NOT NULL,
    "title" TEXT NOT NULL,
    "amount" DECIMAL(12,2) NOT NULL,
    "entryDate" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "LedgerEntry_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "KhataEntry" (
    "id" TEXT NOT NULL,
    "pharmacyId" TEXT NOT NULL,
    "direction" "KhataDirection" NOT NULL,
    "partyName" TEXT NOT NULL,
    "phone" TEXT,
    "amount" DECIMAL(12,2) NOT NULL,
    "paid" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "KhataEntry_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "User_googleSub_key" ON "User"("googleSub");

-- CreateIndex
CREATE UNIQUE INDEX "Pharmacy_ownerId_key" ON "Pharmacy"("ownerId");

-- CreateIndex
CREATE INDEX "Pharmacy_status_idx" ON "Pharmacy"("status");

-- CreateIndex
CREATE INDEX "StockItem_pharmacyId_idx" ON "StockItem"("pharmacyId");

-- CreateIndex
CREATE INDEX "MedRequest_pharmacyId_createdAt_idx" ON "MedRequest"("pharmacyId", "createdAt");

-- CreateIndex
CREATE INDEX "MedRequest_patientId_createdAt_idx" ON "MedRequest"("patientId", "createdAt");

-- CreateIndex
CREATE INDEX "LedgerEntry_pharmacyId_entryDate_idx" ON "LedgerEntry"("pharmacyId", "entryDate");

-- CreateIndex
CREATE INDEX "KhataEntry_pharmacyId_direction_idx" ON "KhataEntry"("pharmacyId", "direction");

-- AddForeignKey
ALTER TABLE "Pharmacy" ADD CONSTRAINT "Pharmacy_ownerId_fkey" FOREIGN KEY ("ownerId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "LicensePhoto" ADD CONSTRAINT "LicensePhoto_pharmacyId_fkey" FOREIGN KEY ("pharmacyId") REFERENCES "Pharmacy"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "StockItem" ADD CONSTRAINT "StockItem_pharmacyId_fkey" FOREIGN KEY ("pharmacyId") REFERENCES "Pharmacy"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "MedRequest" ADD CONSTRAINT "MedRequest_pharmacyId_fkey" FOREIGN KEY ("pharmacyId") REFERENCES "Pharmacy"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "MedRequest" ADD CONSTRAINT "MedRequest_patientId_fkey" FOREIGN KEY ("patientId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RequestItem" ADD CONSTRAINT "RequestItem_requestId_fkey" FOREIGN KEY ("requestId") REFERENCES "MedRequest"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "LedgerEntry" ADD CONSTRAINT "LedgerEntry_pharmacyId_fkey" FOREIGN KEY ("pharmacyId") REFERENCES "Pharmacy"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "KhataEntry" ADD CONSTRAINT "KhataEntry_pharmacyId_fkey" FOREIGN KEY ("pharmacyId") REFERENCES "Pharmacy"("id") ON DELETE CASCADE ON UPDATE CASCADE;
